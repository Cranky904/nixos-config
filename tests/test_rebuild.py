"""Exercise the real runner against fixtures, never against a live rebuild."""

import io
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import termios
import textwrap
import time
import unittest
import fcntl
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import rebuild as app


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.ui = app.Display(self.output, plain=True)
        self.progress = app.Progress(self.ui)
        self.progress.begin("rebuild")

    def event(self, **event):
        self.progress.line("@nix " + json.dumps(event))

    def test_real_warnings_deduplicated_dirty_warning_only_filtered(self):
        self.event(action="msg", level=1, msg="warning: Git tree '/test' is dirty")
        warning = "evaluation warning: GTK default changed.\n  Set an explicit theme."
        self.event(action="msg", level=1, msg=warning)
        self.event(action="msg", level=1, msg=warning)
        self.event(action="msg", level=1, msg="warning: Git tree '/test' has a different problem")
        self.assertEqual(len(self.ui.warnings), 2)
        self.assertNotIn("is dirty", self.output.getvalue())
        self.assertIn("Set an explicit theme", self.output.getvalue())

    def test_lockfile_update_is_a_phase_not_a_warning(self):
        self.progress.begin("update")
        self.event(action="msg", level=1, msg="warning: updating lock file '/repo/flake.lock':\n• Updated input 'nixpkgs'")
        self.assertIn("lockfile", self.ui.rows)
        self.assertFalse(self.ui.warnings)

    def test_concurrent_download_and_build_phases_are_not_finished_by_stop(self):
        self.ui.start("evaluate", "Evaluating", "build")
        self.event(action="start", id=1, type=108, fields=["/nix/store/" + "a" * 32 + "-kitty-1"])
        self.event(action="start", id=2, type=105, fields=["/nix/store/" + "b" * 32 + "-example-2.drv"])
        self.event(action="result", id=2, type=104, fields=["configurePhase"])
        self.assertEqual(self.ui.rows["evaluate"].status, "done")
        self.assertIn("example-2 · configure", self.ui.rows["build"].detail)
        self.event(action="stop", id=2)
        self.assertEqual(self.ui.rows["build"].status, "active")
        self.assertIsNone(self.ui.rows["build"].started)
        self.progress.line("Starting [systemd-run] /nix/store/system/bin/switch-to-configuration switch...")
        self.assertEqual(self.ui.rows["download"].status, "done")
        self.assertEqual(self.ui.rows["build"].status, "done")

    def test_activation_and_git_subphases(self):
        for line in ["Checking switch inhibitors... done", "updating GRUB 2 menu...",
                     "switching to system configuration /nix/store/system", "activating the configuration...",
                     "setting up /etc...", "restarting systemd...", "reloading user units for cranky...",
                     "restarting the following units: home-manager-cranky.service"]:
            self.progress.line(line)
        self.assertEqual(self.ui.rows["bootloader"].status, "done")
        self.assertEqual(self.ui.rows["etc"].status, "done")
        self.assertEqual(self.ui.rows["home"].status, "active")
        self.progress.begin("push")
        for line in ["Enumerating objects: 4, done.", "Compressing objects: 100% (2/2), done.",
                     "Writing objects: 50% (1/2)", "remote: Resolving deltas: 100% (1/1), done."]:
            self.progress.line(line)
        self.assertEqual(self.ui.rows["git-upload"].status, "done")
        self.assertEqual(self.ui.rows["git-remote"].status, "active")

    def test_unknown_or_malformed_events_do_not_break_progress(self):
        for line in ['@nix {"action":"new-event","type":999}', '@nix broken', '@nix []', "a normal log message"]:
            self.progress.line(line)
        self.assertEqual(self.ui.rows, {})

    def test_durations_do_not_include_later_phases(self):
        with patch.object(app.time, "monotonic", return_value=10):
            self.ui.start("first", "First")
        with patch.object(app.time, "monotonic", return_value=12.5):
            self.ui.finish("first")
        with patch.object(app.time, "monotonic", return_value=100):
            self.assertEqual(self.ui.rows["first"].seconds(), 2.5)
        self.assertEqual(app.duration(65), "1m 05s")
        self.assertEqual(app.duration(3661), "1h 01m")

    def test_idle_download_time_is_not_counted_while_waiting_for_build_success(self):
        with patch.object(app.time, "monotonic", return_value=10):
            self.ui.start("download", "Downloading", "build")
        with patch.object(app.time, "monotonic", return_value=12):
            self.ui.wait("download")
        with patch.object(app.time, "monotonic", return_value=100):
            self.ui.finish("download")
        self.assertEqual(self.ui.rows["download"].elapsed, 2)

    def test_animated_error_has_requested_icon_and_restores_cursor(self):
        ui = self.ui
        ui.animated, ui.color = True, True
        ui.start("failed", "Build failed")
        ui.finish("failed", "error")
        ui.close()
        output = self.output.getvalue()
        self.assertIn("\033[31m\uebfb", output)
        self.assertTrue(output.endswith("\033[?25h\033[0m"))

    def test_spinner_tick_preserves_completed_lines_and_never_clears_screen(self):
        self.ui.animated, self.ui.color = True, True
        self.ui.start("finished", "Already completed")
        self.ui.finish("finished")
        self.ui.start("building", "Building packages")
        self.ui.draw(force=True)
        self.output.seek(0)
        self.output.truncate()
        with patch.object(app.time, "monotonic", return_value=time.monotonic() + 0.2):
            self.ui.draw(force=True)
        frame = self.output.getvalue()
        self.assertIn("Building packages", frame)
        self.assertNotIn("Already completed", frame)
        self.assertNotIn("\033[J", frame)
        self.assertNotIn("\033[2K", frame)
        self.assertTrue(frame.startswith("\033[?2026h"))
        self.assertTrue(frame.endswith("\033[?2026l"))

    def test_unchanged_completed_display_writes_nothing(self):
        self.ui.animated = True
        self.ui.start("finished", "Already completed")
        self.ui.finish("finished")
        self.ui.draw(force=True)
        self.output.seek(0)
        self.output.truncate()
        self.ui.draw(force=True)
        self.assertEqual(self.output.getvalue(), "")

    def test_nix_build_totals_are_visible(self):
        self.event(action="start", id=1, type=104)
        self.event(action="start", id=2, type=105, fields=["/nix/store/example.drv"])
        self.event(action="result", id=1, type=105, fields=[5, 46, 1, 0])
        self.assertIn("5/46", self.ui.rows["build"].title)

    def test_compiler_warning_storm_is_counted_per_package_without_flooding_output(self):
        self.event(action="start", id=2, type=105, fields=["/nix/store/" + "a" * 32 + "-nvidia-settings.drv"])
        for i in range(200):
            self.event(action="result", id=2, type=101, fields=[f"driver.c:{i}: warning: deprecated function"])
        warning_rows = [row for row in self.ui.rows.values() if row.status == "warning"]
        self.assertEqual(len(warning_rows), 1)
        self.assertIn("200 build warning(s)", warning_rows[0].title)
        self.assertEqual(self.output.getvalue().count("[WARN]"), 1)

    def test_activation_must_select_the_reported_built_system(self):
        with tempfile.TemporaryDirectory() as root:
            current = Path(root) / "current-system"
            current.symlink_to("/nix/store/old-system")
            self.progress.line("switching to system configuration /nix/store/new-system")
            with self.assertRaises(app.ActivationFailed):
                app.verify_activation(self.progress, current)
            current.unlink()
            current.symlink_to("/nix/store/new-system")
            app.verify_activation(self.progress, current)


FAKE_COMMAND = r'''
import getpass
import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps([command, *args]) + "\n")

def event(**data):
    print("@nix " + json.dumps(data), flush=True)

if command == "sudo":
    if args == ["-v"]:
        if os.environ.get("AUTH_TTY"):
            Path(os.environ["AUTH_TTY"]).write_text(Path("/proc/self/stat").read_text().split()[6])
        sys.exit(0)
    if os.environ.get("AUTH_TTY"):
        previous = Path(os.environ["AUTH_TTY"]).read_text()
        current = Path("/proc/self/stat").read_text().split()[6]
        if previous != current:
            print("sudo: credentials were cached for a different terminal", flush=True)
            sys.exit(18)
    os.execv(str(Path(__file__).parent / args[1]), args[1:])
elif command == "nix":
    event(action="msg", level=1, msg="warning: Git tree '/repo' is dirty")
    event(action="start", id=1, type=112, text="Fetching nixpkgs")
    if os.environ.get("SLOW_UPDATE"):
        import time
        Path(os.environ["SLOW_UPDATE"]).write_text(str(os.getpid()))
        time.sleep(60)
    if os.environ.get("FAIL") == "update":
        event(action="msg", level=0, msg="error: network unavailable")
        sys.exit(7)
    event(action="msg", level=1, msg="warning: updating lock file '/repo/flake.lock':\nUpdated nixpkgs")
elif command == "nixos-rebuild":
    print("building the system configuration...", flush=True)
    event(action="msg", level=1, msg="warning: Git tree '/repo' is dirty")
    event(action="msg", level=1, msg="evaluation warning: a real configuration warning")
    event(action="start", id=3, type=108, fields=["/nix/store/" + "a" * 32 + "-kitty-1"])
    event(action="start", id=4, type=105, fields=["/nix/store/" + "b" * 32 + "-example.drv"])
    event(action="result", id=4, type=104, fields=["buildPhase"])
    if os.environ.get("FAIL") == "rebuild":
        event(action="stop", id=4)
        event(action="msg", level=0, msg="error: compiler exploded")
        sys.exit(8)
    for line in ["Checking switch inhibitors... done", "updating GRUB 2 menu...",
                 "activating the configuration...", "setting up /etc...", "restarting systemd...",
                 "reloading user units for cranky...", "restarting the following units: home-manager-cranky.service"]:
        print(line, flush=True)
elif command == "git":
    if args[0] == "symbolic-ref":
        print("main")
    elif args[0] == "remote":
        print("git@example.com:user/repo.git")
    elif args[0] == "diff":
        if not os.environ.get("NO_CHANGES"):
            print("flake.lock")
    elif args[0] == "log":
        print("Rebuild iteration #7\nRebuild iteration #12\nRebuild iteration #999 invalid")
    elif args[0] == "push":
        if os.environ.get("PROMPT"):
            value = getpass.getpass("Enter passphrase for key '/test/key': ")
            if value != "test-only-passphrase":
                sys.exit(17)
        if os.environ.get("FAIL") == "push":
            print("fatal: remote rejected the update", flush=True)
            sys.exit(9)
        for line in ["Enumerating objects: 4, done.", "Compressing objects: 100% (2/2), done.",
                     "Writing objects: 100% (2/2), done.", "remote: Resolving deltas: 100% (1/1), done."]:
            print(line, flush=True)
    elif args[0] == "commit" and os.environ.get("FAIL") == "commit":
        print("error: a commit hook failed", flush=True)
        sys.exit(10)
'''


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(Path(app.__file__), self.root / "scripts/rebuild.py")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("git", "sudo", "nix", "nixos-rebuild"):
            file = self.bin / name
            file.write_text(f"#!{sys.executable}\n" + textwrap.dedent(FAKE_COMMAND))
            file.chmod(0o755)
        self.env = {**os.environ, "PATH": str(self.bin) + ":" + os.environ["PATH"],
                    "CALLS": str(self.root / "calls"), "XDG_STATE_HOME": str(self.root / "state"),
                    "TERM": "xterm-256color"}
        for key in ("FAIL", "PROMPT", "NO_CHANGES", "NO_COLOR", "SLOW_UPDATE", "AUTH_TTY"):
            self.env.pop(key, None)

    def run_cli(self, **env):
        return subprocess.run([sys.executable, str(self.root / "scripts/rebuild.py")],
                              env={**self.env, **env}, text=True, capture_output=True, timeout=20)

    def calls(self):
        return [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]

    def test_success_preserves_workflow_and_private_logs(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertLess(calls.index(["git", "add", "--all"]), next(i for i, c in enumerate(calls) if c[0] == "nixos-rebuild"))
        self.assertIn(["git", "commit", "-m", "Rebuild iteration #13"], calls)
        self.assertEqual(calls[-1], ["git", "push", "--progress", "--set-upstream", "origin", "HEAD:refs/heads/main"])
        self.assertIn("[WARN] evaluation warning: a real configuration warning", result.stdout)
        self.assertNotIn("is dirty", result.stdout)
        self.assertNotIn("updating lock file", result.stdout)
        self.assertNotIn("\x1b", result.stdout)
        logs = list((self.root / "state/nixos-rebuild").glob("*.log"))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)
        self.assertIn("is dirty", logs[0].read_text())
        self.assertIn("[exit 0; took", logs[0].read_text())
        self.assertIn("[active system]", logs[0].read_text())

    def test_update_failure_stops_before_staging_build_commit_push(self):
        result = self.run_cli(FAIL="update")
        self.assertEqual(result.returncode, 7)
        self.assertIn("error: network unavailable", result.stderr)
        log = next((self.root / "state/nixos-rebuild").glob("*.log")).read_text()
        self.assertIn("[exit 7; took", log)
        self.assertFalse(any(c[0] == "nixos-rebuild" or c[:2] in (["git", "add"], ["git", "commit"], ["git", "push"]) for c in self.calls()))

    def test_build_failure_never_commits_or_pushes_or_marks_build_successful(self):
        result = self.run_cli(FAIL="rebuild")
        self.assertEqual(result.returncode, 8)
        self.assertIn("[ERROR] Building packages", result.stdout)
        self.assertNotIn("[OK] Building packages", result.stdout)
        self.assertIn("error: compiler exploded", result.stderr)
        self.assertFalse(any(c[:2] in (["git", "commit"], ["git", "push"]) for c in self.calls()))

    def test_push_failure_keeps_successful_commit(self):
        result = self.run_cli(FAIL="push")
        self.assertEqual(result.returncode, 9)
        self.assertIn(["git", "commit", "-m", "Rebuild iteration #13"], self.calls())
        self.assertNotIn("NixOS and Home Manager updated", result.stdout)
        self.assertFalse(any(c[:2] in (["git", "reset"], ["git", "revert"]) for c in self.calls()))

    def test_commit_failure_stops_before_push(self):
        result = self.run_cli(FAIL="commit")
        self.assertEqual(result.returncode, 10)
        self.assertFalse(any(c[:2] == ["git", "push"] for c in self.calls()))

    def test_no_changes_skips_commit_but_still_pushes(self):
        result = self.run_cli(NO_CHANGES="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[:2] == ["git", "commit"] for c in self.calls()))
        self.assertEqual(self.calls()[-1][1], "push")

    def test_real_pty_ssh_prompt_remains_interactive_and_secret_is_not_logged(self):
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        def terminal_session():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        process = subprocess.Popen([sys.executable, str(self.root / "scripts/rebuild.py")],
                                   stdin=slave, stdout=slave, stderr=slave,
                                   env={**self.env, "PROMPT": "1", "AUTH_TTY": str(self.root / "auth-tty")},
                                   preexec_fn=terminal_session)
        output, sent = b"", False
        deadline = time.monotonic() + 20
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    chunk = os.read(master, 65536)
                    output += chunk
                    if b"Enter passphrase for key" in output and not sent:
                        os.write(master, b"test-only-passphrase\r")
                        sent = True
                if process.poll() is not None:
                    break
            self.assertEqual(process.wait(timeout=1), 0, output.decode(errors="replace"))
            self.assertTrue(sent)
            self.assertEqual(termios.tcgetattr(slave), before)
            self.assertTrue(b"\x1b[34m" in output, "Missing blue spinner color")
            self.assertIn("\uf42e".encode(), output)
            self.assertNotIn(b"test-only-passphrase", output)
            log = next((self.root / "state/nixos-rebuild").glob("*.log")).read_text()
            self.assertNotIn("test-only-passphrase", log)
            self.assertIn("\x1b[?25h", output.decode(errors="replace"))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)

    def test_interrupt_terminates_child_and_never_commits_or_pushes(self):
        ready = self.root / "slow-update.pid"
        process = subprocess.Popen([sys.executable, str(self.root / "scripts/rebuild.py")],
                                   env={**self.env, "SLOW_UPDATE": str(ready)},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(ready.exists(), "Mock update never started")
            pid = int(ready.read_text())
            process.send_signal(signal.SIGINT)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130, stdout + stderr)
            self.assertIn("[ERROR] Rebuild interrupted", stdout)
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
            self.assertFalse(any(c[:2] in (["git", "commit"], ["git", "push"]) for c in self.calls()))
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    unittest.main()

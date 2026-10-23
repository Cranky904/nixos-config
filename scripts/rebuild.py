#!/usr/bin/env python3
"""Quiet, phase-aware NixOS rebuilds using only the Python standard library."""

from __future__ import annotations

import argparse
import codecs
from collections import deque
from dataclasses import dataclass
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import termios
import textwrap
import time
import tty


FRAMES = tuple(chr(c) for c in range(0xEE06, 0xEE0C))
ICONS = {"done": "\uf42e", "warning": "\uf071", "error": "\uebfb"}
COLORS = {"active": "34", "done": "32", "warning": "33", "error": "31"}
ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")
DIRTY = re.compile(r"^warning: Git tree '[^\n]+' is dirty\s*$")
PROMPT = re.compile(
    r"(?:pass(?:word|phrase)|pin|username|verification code)[^\r\n]*[:?]\s*$"
    r"|\(yes/no[^\r\n]*\)\?\s*$",
    re.IGNORECASE,
)


def clean(text: str) -> str:
    return "".join(c for c in ANSI.sub("", text) if c in "\n\t" or ord(c) >= 32 and ord(c) != 127)


def duration(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.1f}s" if seconds < 10 else f"{seconds:.0f}s"
    minutes, sec = divmod(int(seconds), 60)
    if minutes < 60:
        return f"{minutes}m {sec:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m"


@dataclass
class Row:
    title: str
    group: str
    status: str = "active"
    detail: str = ""
    started: float | None = None
    elapsed: float = 0

    def seconds(self) -> float:
        return self.elapsed + (time.monotonic() - self.started if self.started is not None else 0)


class Display:
    def __init__(self, stream=sys.stdout, plain: bool = False):
        self.stream = stream
        self.animated = stream.isatty() and os.environ.get("TERM") != "dumb" and not plain
        self.color = self.animated and "NO_COLOR" not in os.environ
        self.rows: dict[str, Row] = {}
        self.drawn = 0
        self.screen: list[str] = []
        self.frame = 0
        self.last_draw = 0.0
        self.closed = False
        self.warnings: set[str] = set()
        self.warning_groups: dict[str, int] = {}
        self.paused = False

    def paint(self, text: str, code: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.color else text

    def start(self, key: str, title: str, group: str = "", detail: str = "") -> None:
        row = self.rows.get(key)
        announce = row is None or row.status != "active"
        if row is None:
            row = self.rows[key] = Row(title, group)
        row.title, row.detail = title, clean(detail).replace("\n", " ")
        if row.started is None:
            row.status, row.started = "active", time.monotonic()
            if not self.animated and announce:
                print(f"... {title}", file=self.stream, flush=True)
        self.draw()

    def detail(self, key: str, detail: str) -> None:
        if key in self.rows:
            self.rows[key].detail = clean(detail).replace("\n", " ")

    def finish(self, key: str, status: str = "done") -> None:
        row = self.rows.get(key)
        if row is None or row.status != "active":
            return
        row.elapsed = row.seconds()
        row.started, row.status, row.detail = None, status, ""
        if not self.animated:
            icon = {"done": "[OK]", "warning": "[WARN]", "error": "[ERROR]"}[status]
            print(f"{icon} {row.title}  took {duration(row.elapsed)}", file=self.stream, flush=True)
        self.draw()

    def wait(self, key: str) -> None:
        row = self.rows.get(key)
        if row is not None and row.started is not None:
            row.elapsed = row.seconds()
            row.started = None
            row.detail = "waiting for Nix to confirm"

    def finish_group(self, group: str, status: str = "done") -> None:
        for key, row in list(self.rows.items()):
            if row.group == group:
                self.finish(key, status)

    def warning(self, message: str, group: str | None = None) -> None:
        message = clean(message).strip()
        if not message or DIRTY.fullmatch(message) or message in self.warnings:
            return
        self.warnings.add(message)
        if group is not None:
            count = self.warning_groups[group] = self.warning_groups.get(group, 0) + 1
            summary = f"{group}: {count} build warning(s) (details in log)"
            self.rows[f"build-warning-{group}"] = Row(summary, "warning", "warning")
            if not self.animated and count == 1:
                print(f"[WARN] {group}: build warnings (details in log)", file=self.stream, flush=True)
        else:
            self.rows[f"warning-{len(self.warnings)}"] = Row(message, "warning", "warning")
        if not self.animated and group is None:
            print(f"[WARN] {message}", file=self.stream, flush=True)
        self.draw()

    def clear(self) -> None:
        if self.drawn:
            self.stream.write(f"\033[{self.drawn}A\r\033[J")
            self.drawn = 0
        self.screen = []

    def draw(self, force: bool = False) -> None:
        if not self.animated or self.paused or self.closed:
            return
        now = time.monotonic()
        if not force and now - self.last_draw < 0.08:
            return
        self.last_draw = now
        self.frame = int(now / 0.09)
        size = shutil.get_terminal_size((100, 24))
        width = max(20, size.columns - 1)
        lines = []
        for row in self.rows.values():
            if row.status == "warning":
                for i, line in enumerate(textwrap.wrap(" ".join(row.title.split()), max(10, width - 3))):
                    prefix = ICONS["warning"] if i == 0 else " "
                    lines.append(self.paint(f"{prefix}  {line}", "33"))
                continue
            icon = FRAMES[self.frame % len(FRAMES)] if row.status == "active" else ICONS[row.status]
            suffix = f"  {'elapsed' if row.status == 'active' else 'took'} {duration(row.seconds())}"
            available = max(4, width - len(suffix) - 3)
            label = row.title + (f" · {row.detail}" if row.detail else "")
            if len(label) > available:
                label = label[: available - 1] + "…"
            lines.append(self.paint(icon, COLORS[row.status]) + "  " + self.paint(label, "97") + self.paint(suffix, "90"))
        # Never move the cursor above the viewport on small terminals.
        limit = max(2, size.lines - 2)
        if len(lines) > limit:
            earlier = len(lines) - limit + 1
            lines = [self.paint(f"   … {earlier} earlier progress lines", "90")] + lines[-(limit - 1):]
        # Keep unchanged lines intact. Erasing the entire display before each
        # frame made every label blink, especially with lots of build events.
        # Write over changed lines first, then erase only leftover characters.
        height = max(self.drawn, len(lines))
        updates = []
        if len(lines) > self.drawn:
            updates.append("\n" * (len(lines) - self.drawn))
        for index in range(height):
            previous = self.screen[index] if index < len(self.screen) else None
            current = lines[index] if index < len(lines) else ""
            if current != previous:
                distance = height - index
                updates.append(f"\033[{distance}A\r{current}\033[K\033[{distance}B\r")
        if self.drawn > len(lines):
            updates.append(f"\033[{self.drawn - len(lines)}A\r")
        if updates:
            # Synchronized output is supported by Kitty; terminals that don't
            # implement it ignore the mode and still receive one complete write.
            self.stream.write("\033[?2026h\033[?25l" + "".join(updates) + "\033[?2026l")
            self.stream.flush()
        self.drawn = len(lines)
        self.screen = lines

    def pause(self) -> None:
        if self.animated:
            self.clear()
            self.stream.write("\033[?25h")
            self.stream.flush()
        self.paused = True

    def resume(self) -> None:
        self.paused = False
        self.draw(force=True)

    def close(self) -> None:
        if self.animated and not self.closed:
            self.draw(force=True)
            self.stream.write("\033[?25h\033[0m")
            self.stream.flush()
        self.closed = True


def package_name(path: str) -> str:
    return re.sub(r"^[a-z0-9]{32}-", "", Path(path).name).removesuffix(".drv")


class Progress:
    """Nix 2.34 activity IDs, plus switch-to-configuration and Git progress.

    Protocol: NixOS/nix src/libutil/include/nix/util/logging.hh.
    Unknown events remain in the full log and never invent a completed phase.
    """

    def __init__(self, display: Display):
        self.ui = display
        self.stage = ""
        self.activities: dict[int, dict] = {}
        self.tail: deque[str] = deque(maxlen=30)
        self.plain_warning = False
        self.errors: list[str] = []
        self.target: Path | None = None

    def begin(self, stage: str) -> None:
        self.stage = stage
        self.activities.clear()
        self.tail.clear()
        self.plain_warning = False
        self.errors.clear()
        if stage == "rebuild":
            self.target = None

    def diagnostic(self, text: str, level: int | None = None, warning_group: str | None = None) -> None:
        text = clean(text).strip()
        if not text or DIRTY.fullmatch(text):
            self.plain_warning = False
            return
        self.tail.extend(text.splitlines())
        if self.stage == "update" and re.match(r"(?:warning: )?(?:updating|creating) lock file", text, re.I):
            self.ui.start("lockfile", "Writing updated flake lockfile", "update")
            return
        if level == 0 or re.search(r"(?:^|\s)(?:error|fatal):", text, re.I):
            self.errors.append(text)
        if level == 1 or re.search(r"(?:^|\s)(?:evaluation warning|warning|warn):", text, re.I):
            self.ui.warning(text, group=warning_group)

    def line(self, raw: str) -> None:
        line = clean(raw).strip()
        if not line:
            return
        if line.startswith("@nix "):
            try:
                event = json.loads(line[5:])
                if isinstance(event, dict):
                    self.event(event)
                    return
            except (ValueError, TypeError):
                pass
        self.diagnostic(line)
        if self.plain_warning and raw[:1].isspace():
            self.ui.warning(line)
        self.plain_warning = bool(re.search(r"(?:^|\s)warning:", line, re.I)) and not DIRTY.fullmatch(line)
        lower = line.lower()
        if self.stage == "rebuild":
            target = re.search(r"(?:switching to system configuration|new configuration is) (/nix/store/[^\s]+)", line)
            if target:
                self.target = Path(target.group(1))
            self.activation(lower)
        elif self.stage == "push":
            for marker, key, title in [
                ("enumerating objects:", "git-enumerate", "Preparing Git objects"),
                ("counting objects:", "git-enumerate", "Preparing Git objects"),
                ("compressing objects:", "git-compress", "Compressing Git objects"),
                ("writing objects:", "git-upload", "Uploading Git objects"),
                ("resolving deltas:", "git-remote", "Updating the remote branch"),
            ]:
                if marker in lower:
                    for other in ("git-enumerate", "git-compress", "git-upload"):
                        if other != key:
                            self.ui.finish(other)
                    detail = line.split(":", 1)[-1].strip()
                    self.ui.start(key, title, "push", detail)
                    break

    def event(self, event: dict) -> None:
        action, kind = event.get("action"), event.get("type")
        activity_id, fields = event.get("id"), event.get("fields", [])
        if action == "msg":
            self.diagnostic(str(event.get("msg", "")), event.get("level"))
        elif action == "start":
            self.activities[activity_id] = event
            text = clean(str(event.get("text", "")))
            if self.stage == "update" and kind in (101, 112):
                self.ui.start("sources", "Fetching flake sources", "update", text)
            elif self.stage == "rebuild":
                if kind in (100, 108):
                    self.ui.finish("evaluate")
                    path = str(fields[0]) if fields else text
                    self.ui.start("download", "Downloading dependencies", "build", package_name(path))
                elif kind == 105:
                    self.ui.finish("evaluate")
                    path = str(fields[0]) if fields else text
                    self.ui.start("build", "Building packages", "build", package_name(path))
        elif action == "result":
            activity = self.activities.get(activity_id, {})
            if self.stage == "rebuild" and kind == 104 and fields:
                path_fields = activity.get("fields", [])
                name = package_name(str(path_fields[0])) if path_fields else "package"
                phase = re.sub(r"([a-z])([A-Z])", r"\1 \2", str(fields[0])).removesuffix(" Phase").lower()
                self.ui.start("build", "Building packages", "build", f"{name} · {phase}")
            elif kind == 101 and fields:
                path_fields = activity.get("fields", [])
                group = package_name(str(path_fields[0])) if path_fields else "Package build"
                self.diagnostic(str(fields[0]), warning_group=group)
            elif kind == 105 and len(fields) >= 2:
                if activity.get("type") in (103, 104) and self.stage == "rebuild":
                    key = "build" if activity["type"] == 104 else "download"
                    row = self.ui.rows.get(key)
                    done, total = fields[:2]
                    if row is not None and isinstance(done, int) and isinstance(total, int) and total:
                        label = "Building packages" if key == "build" else "Downloading dependencies"
                        row.title = f"{label} · {done}/{total}"
                elif activity.get("type") == 101 and self.stage == "rebuild":
                    done, total = fields[:2]
                    if isinstance(done, int) and isinstance(total, int) and total:
                        self.ui.detail("download", f"{done / 1048576:.1f} / {total / 1048576:.1f} MiB · current transfer")
        elif action == "stop":
            # Stop events also occur on failure, so wait for activation / exit.
            ended = self.activities.pop(activity_id, {})
            for types, key in [((100, 108), "download"), ((105,), "build"), ((101, 112), "sources")]:
                if ended.get("type") in types and not any(a.get("type") in types for a in self.activities.values()):
                    self.ui.wait(key)

    def activation(self, line: str) -> None:
        if "starting [systemd-run]" in line or "checking switch inhibitors" in line:
            self.ui.finish_group("build")
            self.ui.start("inhibitors", "Checking activation inhibitors", "activate")
            if "done" in line:
                self.ui.finish("inhibitors")
        elif "updating grub" in line:
            self.ui.finish_group("build")
            self.ui.finish("inhibitors")
            self.ui.start("bootloader", "Updating the GRUB boot menu", "activate")
        elif "switching to system configuration" in line or "activating the configuration" in line:
            self.ui.finish_group("build")
            self.ui.finish("inhibitors")
            self.ui.finish("bootloader")
            self.ui.start("activate", "Activating system configuration", "activate")
        elif "setting up /etc" in line:
            self.ui.finish("activate")
            self.ui.start("etc", "Updating /etc", "activate")
        elif "restarting systemd" in line:
            self.ui.finish("etc")
            self.ui.start("services", "Reloading system services", "activate")
        elif "reloading user units" in line or "restarting the following user units" in line:
            self.ui.start("user-services", "Reloading user services", "activate")
        elif "home-manager-" in line and ("restarting" in line or "starting" in line):
            self.ui.start("home", "Applying Home Manager", "activate")
        elif "restarting the following units" in line or "starting the following units" in line:
            self.ui.start("services", "Reloading system services", "activate")


class CommandFailed(Exception):
    def __init__(self, code: int):
        self.code = code if code > 0 else 128 - code


class ActivationFailed(Exception):
    pass


def verify_activation(progress: Progress, current: Path = Path("/run/current-system")) -> None:
    if progress.target is not None and current.resolve() != progress.target:
        raise ActivationFailed(f"Activation did not select the built system: expected {progress.target}, active {current.resolve()}")


class Runner:
    def __init__(self, display: Display, log, progress: Progress):
        self.ui, self.log, self.progress = display, log, progress

    def run(self, args: list[str], stage: str, interactive: bool = False, capture: bool = False) -> str:
        command_started = time.monotonic()
        self.progress.begin(stage)
        self.log.write(f"\n$ {shlex.join(args)}\n")
        self.log.flush()
        # A controlling PTY keeps SSH/Git/GPG prompts visible. Input is never logged.
        use_pty = interactive and sys.stdin.isatty() and self.ui.stream.isatty()
        master = slave = None
        if use_pty:
            master, slave = pty.openpty()
            size = shutil.get_terminal_size((100, 24))
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", size.lines, size.columns, 0, 0))

            def child_terminal():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

            process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, preexec_fn=child_terminal)
            os.close(slave)
            fd = master
        else:
            # Keep the controlling terminal: sudo's cached credentials are tied
            # to it. A separate process group still lets Ctrl+C stop child work.
            process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, process_group=0)
            fd = process.stdout.fileno()
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        pending, output = "", []
        terminal_settings = None
        prompting = False

        def consume(text: str):
            nonlocal pending
            pending += text
            parts = re.split(r"[\r\n]", pending)
            pending = parts.pop()
            for line in parts:
                if line:
                    self.log.write(line + "\n")
                    if capture:
                        output.append(line)
                    self.progress.line(line)
            self.log.flush()

        try:
            while True:
                readers = [fd] + ([sys.stdin.fileno()] if prompting else [])
                ready, _, _ = select.select(readers, [], [], 0.09)
                if prompting and sys.stdin.fileno() in ready:
                    typed = os.read(sys.stdin.fileno(), 1024)
                    os.write(master, typed)
                    if b"\r" in typed or b"\n" in typed:
                        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, terminal_settings)
                        terminal_settings, prompting = None, False
                        self.ui.stream.write("\n")
                        self.ui.resume()
                if fd in ready:
                    try:
                        data = os.read(fd, 65536)
                    except OSError as exc:
                        if exc.errno != errno.EIO:
                            raise
                        data = b""
                    if not data:
                        break
                    text = decoder.decode(data)
                    if prompting:
                        self.ui.stream.write(clean(text))
                        self.ui.stream.flush()
                    else:
                        candidate = pending + text
                        last_line = re.split(r"[\r\n]", candidate)[-1]
                        if use_pty and PROMPT.search(clean(last_line)):
                            prefix = candidate[:len(candidate) - len(last_line)]
                            pending = ""
                            consume(prefix)
                            self.ui.pause()
                            # Switch before displaying the prompt. TCSAFLUSH
                            # would discard a fast paste/password-manager reply.
                            terminal_settings = termios.tcgetattr(sys.stdin)
                            tty.setraw(sys.stdin, when=termios.TCSANOW)
                            prompting = True
                            self.ui.stream.write(clean(last_line))
                            self.ui.stream.flush()
                        else:
                            consume(text)
                self.ui.draw()
            consume(decoder.decode(b"", final=True))
            if pending:
                self.log.write(pending + "\n")
                if capture:
                    output.append(pending)
                self.progress.line(pending)
            code = process.wait()
            if code:
                raise CommandFailed(code)
            return "\n".join(output)
        except BaseException:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
        finally:
            self.log.write(f"[exit {process.returncode}; took {duration(time.monotonic() - command_started)}] {shlex.join(args)}\n")
            self.log.flush()
            if terminal_settings is not None:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, terminal_settings)
            if self.ui.paused:
                self.ui.resume()
            if master is not None:
                os.close(master)
            elif process.stdout:
                process.stdout.close()


def rebuild(runner: Runner, ui: Display) -> None:
    ui.start("prepare", "Checking the repository", "prepare")
    branch = runner.run(["git", "symbolic-ref", "--short", "HEAD"], "prepare", capture=True).strip()
    runner.run(["git", "remote", "get-url", "origin"], "prepare")
    ui.finish_group("prepare")

    ui.start("auth", "Authenticating sudo", "auth")
    runner.progress.begin("auth")
    ui.pause()
    try:
        subprocess.run(["sudo", "-v"], check=True)
    finally:
        ui.resume()
    ui.finish_group("auth")

    ui.start("update", "Updating flake inputs", "update")
    runner.run(["nix", "--log-format", "internal-json", "flake", "update"], "update")
    ui.finish_group("update")

    ui.start("stage", "Staging configuration and lockfile", "stage")
    runner.run(["git", "add", "--all"], "stage")
    ui.finish_group("stage")

    # Refresh after long input updates, with password prompts outside the UI.
    runner.progress.begin("auth")
    ui.pause()
    try:
        subprocess.run(["sudo", "-v"], check=True)
    finally:
        ui.resume()
    ui.start("evaluate", "Evaluating NixOS and Home Manager", "build")
    runner.run(["sudo", "-n", "nixos-rebuild", "switch", "--flake", ".#nixos",
                "--log-format", "internal-json"], "rebuild")
    ui.start("verify", "Confirming the active system", "activate")
    verify_activation(runner.progress)
    runner.log.write(f"[active system] {Path('/run/current-system').resolve()}\n")
    runner.log.flush()
    ui.finish_group("build")
    ui.finish_group("activate")

    ui.start("commit", "Saving the successful rebuild", "commit")
    changed = runner.run(["git", "diff", "--cached", "--name-only"], "commit", capture=True)
    if changed.strip():
        subjects = runner.run(["git", "log", "--all", "--format=%s"], "commit", capture=True)
        iterations = [int(m.group(1)) for m in re.finditer(r"^Rebuild iteration #(\d+)$", subjects, re.M)]
        iteration = max(iterations, default=0) + 1
        runner.run(["git", "commit", "-m", f"Rebuild iteration #{iteration}"], "commit", interactive=True)
        ui.rows["commit"].title = f"Saved Rebuild iteration #{iteration}"
    else:
        ui.rows["commit"].title = "No configuration changes to commit"
    ui.finish_group("commit")

    ui.start("push", f"Pushing {branch} to origin", "push")
    runner.run(["git", "push", "--progress", "--set-upstream", "origin", f"HEAD:refs/heads/{branch}"],
               "push", interactive=True)
    ui.finish_group("push")


def demo(ui: Display) -> None:
    """Replay events without commands, authentication, or Git writes."""
    progress = Progress(ui)

    def wait():
        for _ in range(6):
            time.sleep(0.09)
            ui.draw()

    ui.start("update", "Updating flake inputs", "update")
    progress.begin("update")
    progress.line("warning: Git tree '/demo' is dirty")
    progress.event({"action": "start", "id": 1, "type": 112, "text": "github:NixOS/nixpkgs"})
    wait()
    ui.finish_group("update")
    ui.start("stage", "Staging configuration and lockfile", "stage")
    wait()
    ui.finish_group("stage")
    progress.begin("rebuild")
    ui.start("evaluate", "Evaluating NixOS and Home Manager", "build")
    wait()
    progress.event({"action": "start", "id": 2, "type": 108, "fields": ["/nix/store/" + "a" * 32 + "-kitty-0.44"]})
    wait()
    progress.event({"action": "start", "id": 3, "type": 105, "fields": ["/nix/store/" + "b" * 32 + "-home-manager-generation.drv"]})
    progress.event({"action": "result", "id": 3, "type": 104, "fields": ["installPhase"]})
    wait()
    progress.event({"action": "msg", "level": 1, "msg": "warning: Example warning — your real warnings appear here."})
    wait()
    for line in ["Checking switch inhibitors... done", "updating GRUB 2 menu...",
                 "activating the configuration...", "setting up /etc...", "restarting systemd...",
                 "reloading user units for cranky...", "restarting the following units: home-manager-cranky.service"]:
        progress.line(line)
        wait()
    ui.finish_group("activate")
    ui.start("commit", "Saving the successful rebuild", "commit")
    wait()
    ui.finish_group("commit")
    ui.start("push", "Pushing main to origin", "push")
    progress.begin("push")
    for line in ["Enumerating objects: 9, done.", "Compressing objects: 100% (5/5), done.",
                 "Writing objects: 100% (5/5), done.", "remote: Resolving deltas: 100% (4/4), done."]:
        progress.line(line)
        wait()
    ui.finish_group("push")


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebuild NixOS and Home Manager with readable phase progress.")
    parser.add_argument("--demo", action="store_true", help="preview the UI without changing anything")
    parser.add_argument("--plain", action="store_true", help="disable animation, colors, and Nerd Font icons")
    args = parser.parse_args()
    ui = Display(plain=args.plain)
    started = time.monotonic()
    log_path = None
    log = None
    progress = Progress(ui)
    try:
        if args.demo:
            demo(ui)
        else:
            os.chdir(Path(__file__).resolve().parent.parent)
            log_dir = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "nixos-rebuild"
            log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            log_path = log_dir / f"rebuild-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}.log"
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            log = os.fdopen(fd, "w", encoding="utf-8")
            rebuild(Runner(ui, log, progress), ui)
        ui.close()
        label = "Preview finished" if args.demo else "NixOS and Home Manager updated"
        print(f"\n{label} · took {duration(time.monotonic() - started)}")
        if log_path:
            print(f"Full log: {log_path}")
        if ui.warnings:
            icon = ICONS["warning"] if ui.animated else "[WARN]"
            detail = "shown in this preview" if args.demo else "above; details are in the log"
            print(ui.paint(f"{icon} {len(ui.warnings)} warning(s) {detail}.", "33"))
        return 0
    except (CommandFailed, ActivationFailed, subprocess.CalledProcessError, OSError, KeyboardInterrupt) as exc:
        if isinstance(exc, KeyboardInterrupt):
            code, message = 130, "Rebuild interrupted"
        elif isinstance(exc, CommandFailed):
            code, message = exc.code, f"Command failed (exit {exc.code})"
        elif isinstance(exc, subprocess.CalledProcessError):
            code, message = exc.returncode, "Sudo authentication failed"
        else:
            code, message = 1, clean(str(exc))
        for key in list(ui.rows):
            ui.finish(key, "error")
        ui.start("failure", message)
        ui.finish("failure", "error")
        ui.close()
        diagnostics = [line for message in progress.errors for line in message.splitlines()] or list(progress.tail)
        if diagnostics:
            print("\n".join(diagnostics[-12:]), file=sys.stderr)
        if log_path:
            print(f"\nFull log: {log_path}", file=sys.stderr)
        return code
    finally:
        ui.close()
        if log:
            log.close()


if __name__ == "__main__":
    sys.exit(main())

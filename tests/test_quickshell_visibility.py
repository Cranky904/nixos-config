"""Exercise the clock's actual QML state controller without desktop input."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which("qs") and shutil.which("nix"), "requires Quickshell and Nix")
class ClockVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module = Path(__file__).resolve().parents[1] / "home-modules/quickshell.nix"
        # Evaluate only the controller text; no flake inputs, build, or activation.
        expression = (
            f"let module = import {json.dumps(str(module))} "
            '{ pkgs.writeText = name: text: text; }; '
            'in module.xdg.configFile."quickshell/ClockVisibility.qml".source'
        )
        cls.controller = subprocess.check_output(
            ["nix", "eval", "--impure", "--raw", "--expr", expression], text=True
        )

    def run_scenario(self, initial, later=None):
        with tempfile.TemporaryDirectory(prefix="clock-visibility-") as directory:
            path = Path(directory)
            (path / "ClockVisibility.qml").write_text(self.controller)
            finish = 'console.log("CLOCK_TEST_PASSED");'
            delayed = (
                "Timer { interval: 200; running: true; onTriggered: { " + later + finish + " } }"
                if later is not None else ""
            )
            (path / "shell.qml").write_text(
                "import Quickshell\nimport QtQuick\nScope {\n"
                "ClockVisibility { id: state }\n"
                'function check(value, message) { if (!value) throw new Error(message); }\n'
                "Component.onCompleted: { " + initial + (finish if later is None else "") + " }\n"
                + delayed + "\n}\n"
            )
            environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"}
            environment.pop("WAYLAND_DISPLAY", None)
            with (path / "output.log").open("w") as output:
                process = subprocess.Popen(
                    ["qs", "--no-color", "--path", str(path)],
                    stdout=output, stderr=subprocess.STDOUT, env=environment,
                )
                try:
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        log = (path / "output.log").read_text()
                        if "CLOCK_TEST_PASSED" in log or process.poll() is not None:
                            break
                        time.sleep(0.02)
                    self.assertIn("CLOCK_TEST_PASSED", log, log)
                    self.assertNotIn("ReferenceError", log, log)
                    self.assertNotIn("TypeError", log, log)
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()

    def test_idle_reveals_and_activity_hides(self):
        self.run_scenario('''
            check(!state.compact, "start hidden");
            state.idle = true;
            check(state.compact, "idle reveals");
            state.idle = false;
            state.activity();
            check(!state.compact, "input dismisses idle reveal");
        ''')

    def test_corner_entry_hold_keyboard_and_exit(self):
        self.run_scenario('''
            state.cursorSample(100, 100, 0, 0);
            state.activity();
            state.cursorSample(2, 2, 0, 0);
            check(state.compact, "corner movement reveals despite activity");
            state.cursorSample(2, 2, 0, 0);
            check(state.compact, "stationary corner stays revealed");
            state.activity();
            state.cursorSample(2, 2, 0, 0);
            check(!state.compact, "key or click dismisses a stationary corner");
            state.cursorSample(100, 100, 0, 0);
            state.cursorSample(3, 3, 0, 0);
            check(state.compact, "reentry reveals again");
            state.activity();
            state.cursorSample(4, 4, 0, 0);
            check(state.compact, "movement within the corner keeps the reveal");
            state.cursorSample(8, 4, 0, 0);
            check(!state.compact, "leaving the corner hides");
        ''')

    def test_corner_uses_main_monitor_coordinates(self):
        self.run_scenario('''
            state.cursorSample(0, 0, 1920, 100);
            check(!state.compact, "another monitor's corner does not reveal");
            state.cursorSample(1920, 100, 1920, 100);
            check(state.compact, "main monitor's corner reveals");
            state.cursorSample(1920, 108, 1920, 100);
            check(!state.compact, "corner boundary is eight logical pixels");
        ''')

    def test_fullscreen_overrides_all_reveal_triggers(self):
        self.run_scenario('''
            state.idle = true;
            state.fullscreen = true;
            check(!state.compact, "fullscreen suppresses idle");
            state.workspaceChanged();
            check(!state.compact, "fullscreen suppresses workspace reveal");
            state.cursorSample(1, 1, 0, 0);
            check(!state.compact, "fullscreen suppresses corner reveal");
            state.fullscreen = false;
            check(state.compact, "idle can reveal after fullscreen exits");
            state.idle = false;
            check(!state.compact, "fullscreen does not retain stale reveals");
        ''')

    def test_workspace_reveal_survives_shortcut_then_hides_on_input(self):
        self.run_scenario('''
            state.workspaceChanged();
            check(state.compact, "workspace reveals");
            state.activity();
            check(state.compact, "switch shortcut does not cancel reveal");
        ''', later='''
            state.activity();
            check(!state.compact, "subsequent input dismisses workspace reveal");
        ''')


if __name__ == "__main__":
    unittest.main()

"""Exercise the clock's QML visibility and digit animations without desktop input."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which("qs") and shutil.which("nix"), "requires Quickshell and Nix")
class QmlScenarioTests(unittest.TestCase):
    component_name = "ClockVisibility"
    dependencies = ()

    @classmethod
    def setUpClass(cls):
        module = Path(__file__).resolve().parents[1] / "home-modules/quickshell.nix"
        # Evaluate only the component text; no flake inputs, build, or activation.
        expression = (
            f"let module = import {json.dumps(str(module))} "
            '{ pkgs = { writeText = name: text: text; cava = "/unused-test-cava"; kitty = "/unused-test-command"; systemd = "/unused-test-command"; python3 = "/unused-test-runtime"; "yt-dlp" = "/unused-test-runtime"; ffmpeg = "/unused-test-runtime"; mpv = "/unused-test-runtime"; nodejs = "/unused-test-runtime"; }; }; '
            f'in module.xdg.configFile."quickshell/{cls.component_name}.qml".source'
        )
        cls.controller = subprocess.check_output(
            ["nix", "eval", "--impure", "--raw", "--expr", expression], text=True
        )
        cls.dependency_sources = {}
        for name in cls.dependencies:
            dependency_expression = expression.replace(
                f"/{cls.component_name}.qml", f"/{name}.qml"
            )
            cls.dependency_sources[name] = subprocess.check_output(
                ["nix", "eval", "--impure", "--raw", "--expr", dependency_expression], text=True
            )

    def run_scenario(self, initial, later=None, delay=200):
        with tempfile.TemporaryDirectory(prefix="clock-visibility-") as directory:
            path = Path(directory)
            (path / f"{self.component_name}.qml").write_text(self.controller)
            for name, source in self.dependency_sources.items():
                (path / f"{name}.qml").write_text(source)
            finish = 'console.log("CLOCK_TEST_PASSED");'
            delayed = (
                f"Timer {{ id: scenarioTimer; interval: {delay}; onTriggered: {{ " + later + finish + " } }"
                if later is not None else ""
            )
            (path / "shell.qml").write_text(
                "import Quickshell\nimport QtQuick\nScope {\n"
                f"{self.component_name} {{ id: state }}\n"
                'function check(value, message) { if (!value) throw new Error(message); }\n'
                "Component.onCompleted: Qt.callLater(() => { "
                + initial + (finish if later is None else "scenarioTimer.start();") + " })\n"
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

class AudioServiceTests(QmlScenarioTests):
    component_name = "AudioService"

    def test_scroll_changes_five_points_and_clamps_without_unmuting(self):
        self.run_scenario('''
            state.sink = Qt.createQmlObject('import QtQuick; QtObject { property bool ready: true; property QtObject audio: QtObject { property real volume: 0.8; property bool muted: false } }', state);
            state.scroll(120);
            check(Math.abs(state.sink.audio.volume - 0.85) < 0.0001, "up adds five percentage points");
            state.scroll(-120);
            check(Math.abs(state.sink.audio.volume - 0.8) < 0.0001, "down removes five percentage points");
            state.scroll(1200);
            check(state.sink.audio.volume === 1, "scroll cannot boost beyond 100 percent");
            state.scroll(-3600);
            check(state.sink.audio.volume === 0, "scroll cannot go negative");
            state.sink.audio.muted = true;
            state.scroll(120);
            check(state.sink.audio.muted, "scroll preserves mute");
            state.sink = null;
            state.scroll(120);
            check(!state.available, "missing output is harmless");
        ''')

    def test_high_resolution_scroll_accumulates_and_tracks_external_volume(self):
        self.run_scenario('''
            state.sink = Qt.createQmlObject('import QtQuick; QtObject { property bool ready: true; property QtObject audio: QtObject { property real volume: 0.5; property bool muted: false } }', state);
            state.scroll(60);
            check(state.sink.audio.volume === 0.5, "half notch waits for another half");
            state.scroll(60);
            check(state.sink.audio.volume === 0.55, "two halves form one notch");
            state.sink = Qt.createQmlObject('import QtQuick; QtObject { property bool ready: true; property QtObject audio: QtObject { property real volume: 0.2; property bool muted: false } }', state);
            state.scroll(-120);
            check(state.sink.audio.volume === 0.15, "next scroll uses the current output volume");
            state.scroll(NaN);
            check(state.sink.audio.volume === 0.15, "invalid delta is ignored");
        ''')

    def test_spectrum_frames_replace_all_bands_together_and_reject_bad_data(self):
        self.run_scenario('''
            state.sink = null;
            const bass = Array(16).fill("0"); bass[2] = "850";
            check(state.acceptFrame(bass.join(";") + ";"), "complete CAVA frame is accepted");
            check(state.bands[2] === 0.85 && state.bands[12] === 0, "bass is distinct from treble");
            const treble = Array(16).fill("0"); treble[12] = "700";
            state.acceptFrame(treble.join(";"));
            check(state.bands[2] === 0 && state.bands[12] === 0.7,
                "one current spectrum replaces all bands without history delays");
            check(!state.acceptFrame("1;2;garbage;"), "malformed or incomplete frames are rejected");
            check(state.bands[12] === 0.7, "bad data cannot corrupt the last valid frame");
            state.acceptFrame(Array(16).fill("0").join(";"));
            check(state.bands.every(v => v === 0), "silent audio leaves still dots");
            state.acceptFrame(Array(16).fill("2000").join(";"));
            check(state.bands.every(v => v === 1), "band levels are bounded");
            state.clear();
            check(state.bands.every(v => v === 0), "closing clears stale frequency bands");
            check(!state.capturing, "unavailable output cannot capture");
        ''')

    def test_capture_selects_the_output_monitor(self):
        self.run_scenario('''
            state.sink = Qt.createQmlObject('import QtQuick; QtObject { property string name: "test-output"; property bool ready: true; property QtObject audio: QtObject { property real volume: 0.5; property bool muted: false } }', state);
            check(state.spectrumConfig().includes("source = test-output.monitor"),
                "FFT capture explicitly targets output playback");
            check(state.spectrumConfig().includes("channels = mono"), "bands cover both playback channels");
            check(!state.capturing, "hidden control does not start capture");
        ''')


class AudioOutlineTests(QmlScenarioTests):
    component_name = "AudioOutline"
    dependencies = ("HoverOutline",)

    def test_full_ring_uses_simultaneous_frequency_bands(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.motionEnabled = false;
            check(state.progress === 0, "no dots or bars without hover");
            state.hovered = true;
            check(state.progress === 1, "hover reveals the spectrum");
            state.motionEnabled = true;
            const first = state.pointAt(0), last = state.pointAt(1);
            check(Math.abs(first.x - last.x) < 0.001 && Math.abs(first.y - last.y) < 0.001,
                "outline wraps the complete capsule without a gap");
            check(state.barCount === 16, "fewer, more widely spaced bars");
            check(state.maximumBarLength > state.inset, "bars can grow beyond the glass edge");
            check(state.maximumBarLength / 2 - state.inset + 0.75 < state.overdraw,
                "canvas includes the full bar length and rounded cap");
            state.bands = Array(16).fill(0); state.bands[0] = 0.9; state.bands[8] = 0.5;
            check(state.levelAt(0) === 0.9 && state.levelAt(0.5) === 0.5,
                "bass and treble come from the same current FFT frame");
            check(state.levelAt(0) === state.levelAt(1), "hover waveform closes smoothly");
            state.muted = true;
            check(state.levelAt(0) === 0, "muted output leaves still dots");
            state.muted = false; state.motionEnabled = false;
            check(state.levelAt(0) === 0, "reduced motion keeps a still outline");
        ''')

    def test_directional_draw_and_reduced_motion(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.progress = 0.4;
            check(state.revealAt(0.25) === 1, "leftmost bars draw first");
            check(state.revealAt(0.5) > 0 && state.revealAt(0.5) < 1,
                "top middle bar grows at the travelling front");
            check(state.revealAt(0) === state.revealAt(0.5), "upper and lower halves draw together");
            check(state.revealAt(0.75) === 0, "rightmost bars remain hidden until the front arrives");
            state.progress = 1;
            check(Array.from({length:16}, (_, i) => state.revealAt(i/16)).every(v => v === 1),
                "completed hover covers every frequency band");
            state.motionEnabled = false;
            state.hovered = true;
            check(state.progress === 1, "reduced motion reveals instantly");
            state.hovered = false;
            check(state.progress === 0, "reduced motion hides instantly");
        ''')

    def test_hover_reversal_retracts_without_fading(self):
        self.run_scenario('''
            state.width = 58; state.height = 31; state.hovered = true;
        ''', later='''
            check(state.progress > 0 && state.progress < 1, "hover draws over time");
            check(state.opacity === 1, "hover uses geometry rather than opacity");
            const before = state.progress;
            state.hovered = false;
            check(state.progress === before && state.animating, "leaving reverses from current progress");
            state.motionEnabled = false;
            check(state.progress === 0, "retraction finishes fully hidden");
        ''', delay=100)


class MediaServiceTests(QmlScenarioTests):
    component_name = "MediaService"

    def test_selected_playlist_preview_and_local_playback_metadata(self):
        self.run_scenario('''
            state.externalPlayer = null;
            state.acceptState(JSON.stringify({playlists:[{id:"test",title:"Test"}],tracks:[{id:"a",title:"Track A",artist:"Artist A",art:"file:///art.jpg",state:"ready",skipped:false}],selected:"test",current:{},busy:false,error:""}));
            check(state.title === "Track A" && state.artist === "Artist A" && state.canToggle, "ready playlist provides playable preview");
            state.state = Object.assign({},state.state,{current:{loaded:true,playing:true,title:"Track B",artist:"Artist B",art:"file:///b.jpg"}});
            check(state.local && state.playing && state.title === "Track B", "local player metadata takes over the banner");
            state.state = Object.assign({},state.state,{current:{},tracks:[{id:"a",title:"A",state:"ready",skipped:true}]});
            check(!state.canToggle, "fully excluded playlists cannot start playback");
        ''')

    def test_all_playlist_panels_dismiss_on_outside_click(self):
        self.run_scenario('''
            state.mode="download";state.dismissEditor();check(state.mode==="normal","outside click dismisses URL entry");
            state.mode="choose";state.dismissEditor();check(state.mode==="normal","outside click dismisses playlist chooser");
            state.mode="modify";state.dismissEditor();check(state.mode==="normal","outside click dismisses playlist editing");
            state.mode="download";state.download("https://youtube.com/playlist?list=PLfixture");
            check(state.mode==="normal","submitting a URL restores playlist progress view");
        ''')


    def test_seeking_uses_player_capabilities_and_clamps_to_duration(self):
        self.run_scenario('''
            const player=Qt.createQmlObject('import QtQuick; QtObject {property bool isPlaying:false;property bool canSeek:true;property bool positionSupported:true;property bool lengthSupported:true;property real length:120;property real position:30}',state);
            state.externalPlayer=player;
            check(state.canSeek && state.position===30 && state.duration===120,"external progress uses MPRIS seconds");
            state.seek(72);check(player.position===72,"seeking writes absolute MPRIS position");
            state.seek(-10);check(player.position===0,"seek clamps before the start");
            state.seek(999);check(player.position===120,"seek clamps past the end");
            player.canSeek=false;state.seek(50);check(player.position===120&&!state.canSeek,"unsupported seeking is inert");
            state.state=Object.assign({},state.state,{current:{loaded:true,playing:true,position:8,duration:60}});
            check(state.local&&state.canSeek&&state.position===8&&state.duration===60,"local playback supplies progress");
        ''')


class MediaMorphPanelTests(QmlScenarioTests):
    component_name = "MediaMorphPanel"
    dependencies = ("FrostedSurface",)

    def test_action_button_expands_over_actions_and_playlist_area(self):
        self.run_scenario('''
            state.motionEnabled=false;state.originX=192;
            state.opened=true;
            check(state.width===288&&state.height===380&&state.x===0,"panel covers all action buttons and playlist list");
            state.opened=false;
            check(state.width===88&&state.height===38&&state.x===192&&!state.visible,"panel returns to its original button");
        ''')


class SkyPositionsTests(QmlScenarioTests):
    component_name = "SkyPositions"

    def test_positions_match_suncalc_reference_coordinates(self):
        self.run_scenario('''
            // SunCalc 1.9.0 reference fixture: github.com/mourner/suncalc/blob/v1.9.0/test.js
            state.latitude = 50.5; state.longitude = 30.5;
            state.now = new Date("2013-03-05T00:00:00Z");
            check(Math.abs(state.sun.azimuth - (-2.5003175907168385)) < 1e-8, "solar azimuth matches reference");
            check(Math.abs(state.sun.altitude - (-0.7000406838781611)) < 1e-8, "solar altitude matches reference");
            check(Math.abs(state.moon.azimuth - (-0.9783999522438226)) < 1e-8, "lunar azimuth matches reference");
        ''')

    def test_budapest_sky_projection_and_timezone_offsets(self):
        self.run_scenario('''
            state.now = new Date("2026-03-20T11:00:00Z");
            check(state.sun.altitude > 0 && Math.min(state.sun.phase, 1-state.sun.phase) < 0.05,
                "sun is near the top around Budapest solar noon");
            state.now = new Date("2026-03-20T23:00:00Z");
            check(state.sun.altitude < 0 && Math.abs(state.sun.phase-0.5) < 0.05,
                "sun follows the lower outline below the horizon at night");
            const a = state.position(new Date("2026-10-25T02:30:00+02:00"), false);
            const b = state.position(new Date("2026-10-25T01:30:00+01:00"), false);
            check(Math.abs(a.phase - b.phase) < 1e-10, "DST representations of the same instant have one sky position");
            state.now = new Date("2026-10-10T12:00:00Z");
            const separation = Math.abs(state.sun.phase - state.moon.phase);
            check(Math.abs(separation - 0.5) > 0.1, "moon follows its actual orbit rather than opposing the sun");
        ''')


class CelestialOutlineTests(QmlScenarioTests):
    component_name = "CelestialOutline"
    dependencies = ("HoverOutline",)

    def test_icons_leave_gaps_and_nearby_bodies_remain_legible(self):
        self.run_scenario('''
            state.width = 58; state.height = 31; state.motionEnabled = false;
            state.sunPhase = 0; state.moonPhase = 0.5; state.hovered = true;
            const sun = state.markers[0], moon = state.markers[1];
            check(Math.abs(sun.x-29) < 0.01 && Math.abs(sun.y-3) < 0.01, "high sun sits at the top");
            check(Math.abs(moon.x-29) < 0.01 && Math.abs(moon.y-28) < 0.01, "below-horizon moon sits at the bottom");
            check(state.inGap(sun.x, sun.y) && state.inGap(moon.x, moon.y), "line stops around both icons");
            check(!state.inGap(3,15.5), "border resumes outside icon gaps");
            check(state.iconOpacity(sun) === 1 && state.iconOpacity(moon) === 1, "icons join completed hover");
            state.moonPhase = 0;
            const [a,b] = state.markers;
            check(Math.hypot(a.x-b.x, a.y-b.y) >= state.iconSize+1, "conjunction does not overlap glyphs");
            state.active = false;
            check(state.progress === 0, "calendar expansion or leaving expanded mode removes celestial hover");
        ''')

    def test_border_and_icons_share_the_existing_draw_animation(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.sunPhase = 0; state.moonPhase = 0.5;
            state.hovered = true;
        ''', later='''
            check(state.progress > 0 && state.progress < 1, "outline still draws over time");
            check(state.markers.every(marker => state.iconOpacity(marker) >= 0 && state.iconOpacity(marker) <= 1),
                "glyph reveal stays within the animated border progress");
            state.motionEnabled = false;
            check(state.progress === 1 && state.markers.every(marker => state.iconOpacity(marker) === 1),
                "reduced motion completes border and icons together");
        ''', delay=100)


class BackdropGeometryTests(QmlScenarioTests):
    component_name = "BackdropGeometry"

    def test_visible_windows_follow_active_workspaces_and_screen_bounds(self):
        self.run_scenario('''
            const client = {mapped:true, hidden:false, pinned:false,
                at:[6,6], size:[1908,1068], focusHistoryID:1};
            check(state.fadeWidth === 960, "fade ends at half the main monitor");
            check(state.windowVisible(client, true, 0, 0), "active main-monitor window is streamed");
            check(!state.windowVisible(client, false, 0, 0), "inactive workspace is not streamed");
            client.pinned = true;
            check(state.windowVisible(client, false, 0, 0), "pinned window remains visible across workspaces");
            client.hidden = true;
            check(!state.windowVisible(client, true, 0, 0), "hidden window cannot leak into the backdrop");
            client.hidden = false;
            client.at = [1926,6];
            check(!state.windowVisible(client, true, 0, 0), "secondary display is outside main backdrop");
            check(state.windowVisible(client, true, 1920, 0), "window coordinates account for monitor origin");
        ''')

    def test_blur_padding_keeps_nearby_windows_without_streaming_distant_ones(self):
        self.run_scenario('''
            const client = {mapped:true, at:[1000,20], size:[400,600]};
            check(state.windowVisible(client, true, 0, 0), "window beyond fade still supplies blur-kernel pixels");
            client.at = [1100,20];
            check(!state.windowVisible(client, true, 0, 0), "distant windows need no capture");
            client.at = [10,-700];
            check(!state.windowVisible(client, true, 0, 0), "window above monitor is excluded");
            client.at = [10,10]; client.size = [0,600];
            check(!state.windowVisible(client, true, 0, 0), "zero-sized windows are excluded");
        ''')

    def test_unfocused_windows_stay_above_wallpaper_and_floating_order_is_preserved(self):
        self.run_scenario('''
            const active = {focusHistoryID:0};
            const inactive = {focusHistoryID:12};
            const floating = {focusHistoryID:20, floating:true};
            const fullscreen = {focusHistoryID:30, fullscreen:2};
            check(state.stackingOrder(inactive) > 0, "unfocused windows stay above wallpaper at z=0");
            check(state.stackingOrder(active) > state.stackingOrder(inactive), "recent windows stack above older ones");
            check(state.stackingOrder(floating) > state.stackingOrder(active), "floating windows stay above tiles");
            check(state.stackingOrder(fullscreen) > state.stackingOrder(floating), "fullscreen covers ordinary windows");
        ''')


class MenuEntranceTests(QmlScenarioTests):
    component_name = "MenuEntrance"

    def test_reduced_motion_and_pinned_clock_skip_the_stagger(self):
        self.run_scenario('''
            state.motionEnabled=false;state.order=5;state.open=true;
            check(state.progress===1&&state.offset===0,"reduced motion enters immediately");
            state.open=false;check(state.progress===0&&state.offset===-80,"closed modules start offscreen");
            state.participates=false;
            check(state.progress===1&&state.offset===0,"clock stays anchored for a direct calendar opening");
        ''')

    def test_windows_entry_rearms_a_previously_pinned_clock(self):
        self.run_scenario('''
            state.participates=false;check(state.progress===1,"direct calendar keeps its clock pinned");
            state.participates=true;check(state.progress===0,"Windows prepares the clock offscreen before opening");
            state.open=true;
        ''', later='''
            check(state.progress>0&&state.progress<1&&state.offset<0,"clock actually slides during a Windows opening");
        ''', delay=100)

    def test_later_buttons_wait_before_starting(self):
        self.run_scenario('''
            state.order=4;state.open=true;
        ''', later='''
            check(state.progress===0,"footer waits until top modules have begun entering");
            state.open=false;state.motionEnabled=false;
            check(state.progress===0&&!state.animating,"closing before delayed entry cancels it");
        ''', delay=100)

    def test_next_button_enters_while_previous_would_still_be_moving(self):
        self.run_scenario('''
            state.order=1;state.open=true;
        ''', later='''
            check(state.progress>0&&state.progress<1,"65 ms stagger overlaps the 360 ms entrance");
        ''', delay=180)


class ModuleDeckTests(QmlScenarioTests):
    component_name = "ModuleDeck"

    def test_reduced_motion_opens_switches_and_closes_immediately(self):
        self.run_scenario('''
            state.motionEnabled=false;state.requested="clock";
            check(state.displayed==="clock"&&state.progress===1&&state.interactive,"open calendar immediately");
            state.requested="media";
            check(state.displayed==="media"&&state.progress===1,"switch to media without stale content");
            state.requested="";
            check(state.displayed===""&&state.progress===0&&!state.interactive,"close and release controls");
        ''')

    def test_reversing_current_panel_preserves_its_current_frame(self):
        self.run_scenario('''
            state.requested="clock";
        ''', later='''
            const progress=state.progress;
            check(progress>0.4&&progress<1,"opening eases toward its destination");
            state.requested="";
            check(state.displayed==="clock"&&state.progress===progress&&!state.interactive,"close starts from displayed frame");
            state.requested="clock";
            check(state.progress===progress,"reopening reverses without jumping");
            state.motionEnabled=false;
            check(state.progress===1&&state.interactive,"reduced motion completes the reversal");
        ''', delay=100)

    def test_switch_finishes_old_panel_then_opens_latest_selection(self):
        self.run_scenario('''
            state.motionEnabled=false;state.requested="clock";state.motionEnabled=true;
            state.requested="media";
            check(state.displayed==="clock"&&state.progress===1&&!state.interactive,"outgoing calendar loses input immediately");
            state.requested="usage";
            check(state.displayed==="clock","rapid selection cannot replace outgoing contents mid-animation");
        ''', later='''
            check(state.displayed==="usage"&&state.progress>0&&state.progress<1,"latest selection opens after old panel retracts");
            state.motionEnabled=false;
            check(state.progress===1&&state.interactive,"new panel takes input after opening");
        ''', delay=380)

    def test_close_before_delayed_open_cancels_the_entrance(self):
        self.run_scenario('''
            state.enterDelay=200;state.requested="clock";
        ''', later='''
            check(state.progress===0,"initial calendar waits briefly for the button row");
            state.requested="";
            check(state.displayed===""&&!state.animating&&state.progress===0,"closing during the delay cannot flash a stale panel");
        ''', delay=80)


class SessionActionsTests(QmlScenarioTests):
    component_name = "SessionActions"

    def test_power_commands_require_confirmation_and_cancel_is_inert(self):
        self.run_scenario('''
            const commands=[];state.commandRequested.connect(command=>commands.push(command));
            state.confirm();check(commands.length===0,"confirm without a request is inert");
            state.request("poweroff");check(state.confirming&&commands.length===0,"power opens confirmation only");
            state.cancel();state.confirm();check(commands.length===0&&!state.confirming,"cancel cannot shut down");
            state.request("reboot");check(commands.length===0,"restart opens confirmation only");
            state.confirm();check(commands.length===1&&commands[0][1]==="reboot"&&!state.confirming,"explicit confirmation dispatches restart once");
            state.confirm();check(commands.length===1,"repeated confirmation cannot dispatch again");
            state.request("poweroff");state.confirm();check(commands[1][1]==="poweroff","shutdown uses poweroff");
        ''')

    def test_rebuild_requests_kitty_with_the_script_as_an_argument(self):
        self.run_scenario('''
            const commands=[];state.commandRequested.connect(command=>commands.push(command));
            state.request("unknown");check(commands.length===0,"unknown actions cannot run commands");
            state.request("rebuild");
            check(commands.length===1&&!state.confirming,"rebuild launches directly without power confirmation");
            const command=commands[0];
            check(command[0].endsWith("/bin/kitty")&&command[1]==="--directory","rebuild opens Kitty directly");
            check(command[3]===command[2]+"/./rebuild.sh"&&command[2].endsWith("/nixos-config"),"script and working directory match the requested repository");
        ''')


class ExpandedStateTests(QmlScenarioTests):
    component_name = "ExpandedState"

    def test_windows_opens_collapsed_stack_and_closes_again(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.toggle();
            check(state.open && state.selected === "" && state.progress === 1 && state.clockEntrance,
                "Windows opens the stack without expanding the calendar");
            state.toggle();
            check(!state.open && state.selected === "" && !state.mounted,
                "Windows closes and unmounts the expanded menu");
        ''')

    def test_clock_entry_and_mutually_exclusive_module_selection(self):
        self.run_scenario('''
            state.openWith("clock");
            check(state.open && state.selected === "clock" && !state.clockEntrance, "clock click opens calendar without sliding the clock");
            state.select("media");
            check(state.selected === "media", "opening media replaces calendar selection");
            state.select("invalid");
            check(state.selected === "media", "unknown modules cannot replace a valid selection");
            state.select("media");
            check(state.selected === "", "selecting an open module collapses it");
            state.close();
            state.toggle();
            check(state.selected === "", "a later Windows opening resets to collapsed modules");
        ''')

    def test_blank_space_collapses_only_the_widget(self):
        self.run_scenario('''
            state.motionEnabled=false;state.openWith("media");state.collapse();
            check(state.open&&state.mounted&&state.selected==="","blank menu keeps the main menu open");
        ''')

    def test_rapid_open_close_reverses_without_unmapping_early(self):
        self.run_scenario('''
            state.openWith("clock");
        ''', later='''
            const progress = state.progress;
            check(progress > 0 && progress < 1, "opening has intermediate frames");
            state.close();
            check(state.mounted && state.progress === progress && state.selected === "",
                "closing preserves the current frame while clearing selection");
            state.toggle();
            check(state.progress === progress && state.open,
                "rapid reversal keeps the current animated position");
            state.motionEnabled = false;
            check(state.progress === 1, "reduced motion settles an opening menu");
            state.close();
            check(state.progress === 0 && !state.mounted, "reduced motion closes immediately");
        ''', delay=100)


class ModuleTileTests(QmlScenarioTests):
    component_name = "ModuleTile"
    dependencies = ("HoverOutline",)

    def test_expansion_geometry_and_reduced_motion(self):
        self.run_scenario('''
            state.motionEnabled = false;
            check(state.width === 58 && state.height === 31, "collapsed tile matches compact clock");
            state.expanded = true;
            check(state.width === 600 && state.height === 310 && state.radius === 24,
                "calendar tile expands with rounded glass geometry");
            state.expandedWidth = 420;
            check(state.width === 420, "tile scales to available overlay width");
            state.expanded = false;
            check(state.width === 58 && state.height === 31, "closing returns to original capsule");
        ''')

    def test_shared_morph_disables_capsule_input_and_restores_it_on_return(self):
        self.run_scenario('''
            state.motionEnabled=false;
            const button=state.children.find(item=>item.objectName==="compactButton");
            check(button.visible&&button.enabled,"compact capsule is clickable");
            state.controlledProgress=1;
            check(state.width===600&&state.height===310,"the same surface grows into its panel");
            check(!button.visible&&!button.enabled,"expanded blank space cannot retain a capsule hand cursor");
            state.controlledProgress=0;
            check(state.width===58&&state.height===31&&button.visible&&button.enabled,
                "returning to the row restores the original capsule and input");
        ''')

    def test_expansion_eases_out_and_closing_reverses(self):
        self.run_scenario('''
            state.expanded = true;
        ''', later='''
            check(state.progress > 0.4 && state.progress < 1,
                "opening moves quickly at the start and eases into its final size");
            const progress = state.progress;
            state.expanded = false;
            check(state.progress === progress && state.animating, "collapse starts at current size");
        ''', delay=100)


class CalendarViewTests(QmlScenarioTests):
    component_name = "CalendarView"

    def test_monday_grid_leap_year_and_year_navigation(self):
        self.run_scenario('''
            state.today = new Date(2024, 1, 29, 12);
            check(state.firstDay === 3 && state.daysInMonth === 29, "leap February starts Thursday");
            check(state.dateAt(3).getDate() === 1 && state.dateAt(31).getDate() === 29,
                "Monday-first date cells include leap day");
            check(state.dateAt(0).getMonth() === 0 && state.dateAt(32).getMonth() === 2,
                "adjacent month dates fill the grid correctly");
            state.monthOffset = -2;
            check(state.month.getFullYear() === 2023 && state.month.getMonth() === 11,
                "month navigation crosses year boundaries");
            state.selectedDate = new Date(2023, 11, 10);
            state.reset();
            check(state.monthOffset === 0 && state.sameDay(state.selectedDate, state.today),
                "today shortcut restores month and selected day");
        ''')


class WeatherServiceTests(QmlScenarioTests):
    component_name = "WeatherService"

    def test_budapest_weather_parsing_and_unavailable_states(self):
        self.run_scenario('''
            check(state.city === "Budapest" && !state.available && state.temperatureText === "—",
                "weather starts honestly unavailable instead of displaying dummy temperatures");
            state.accept({current: {temperature_2m: 13.7, apparent_temperature: 11.2,
                wind_speed_10m: 10.8, weather_code: 3, is_day: 1}});
            check(state.available && state.temperatureText === "14°" && state.condition === "Overcast",
                "live response exposes rounded temperature and weather condition");
            let rejected = false;
            try { state.accept({current: {temperature_2m: 999}}); }
            catch (error) { rejected = true; }
            check(rejected && state.temperature === 13.7, "malformed responses preserve the last valid weather");
            state.stale = true;
            check(state.status === "Last update unavailable", "failed refresh labels cached data honestly");
        ''')


class ClockVisibilityTests(QmlScenarioTests):
    def test_menu_close_lingers_for_two_seconds_without_idle_or_hover(self):
        self.run_scenario('''
            state.menuClosed();
            state.cursorSample(1000, 500, 0, 0);
            check(state.menuLinger && state.compact, "closing protects the compact clock from input");
        ''', later='''
            check(state.menuLinger && state.compact, "clock is still shown just before two seconds");
        ''', delay=1900)

    def test_menu_close_linger_expires_and_fullscreen_cancels_it(self):
        self.run_scenario('''
            state.menuClosed();
        ''', later='''
            check(!state.menuLinger && !state.compact, "clock hides once two seconds expire without another trigger");
            state.menuClosed();
            check(state.menuLinger, "another close starts a fresh linger");
            state.fullscreen = true;
            check(!state.menuLinger && !state.compact, "fullscreen cancels the menu linger");
            state.menuClosed();
            check(!state.menuLinger, "closing over fullscreen does not bypass compact suppression");
        ''', delay=2100)

    def test_idle_reveals_and_activity_hides(self):
        self.run_scenario('''
            check(!state.compact, "start hidden");
            state.idle = true;
            check(state.compact, "idle reveals");
            state.idle = false;
            state.idle = false;
            check(!state.compact, "input dismisses idle reveal");
        ''')

    def test_corner_entry_hold_input_and_exit(self):
        self.run_scenario('''
            state.cursorSample(100, 100, 0, 0);
            state.idle = false;
            state.cursorSample(2, 2, 0, 0);
            check(state.compact, "corner movement reveals despite activity");
            state.cursorSample(2, 2, 0, 0);
            check(state.compact, "stationary corner stays revealed");
            state.idle = false;
            state.cursorSample(2, 2, 0, 0);
            check(state.compact, "input does not cancel deliberate corner hover");
            state.cursorSample(100, 100, 0, 0);
            state.cursorSample(3, 3, 0, 0);
            check(state.compact, "reentry reveals again");
            state.idle = false;
            state.cursorSample(4, 4, 0, 0);
            check(state.compact, "movement within the corner keeps the reveal");
            state.cursorSample(80, 4, 0, 0);
            check(!state.compact, "leaving the corner hides");
        ''')

    def test_corner_uses_main_monitor_coordinates(self):
        self.run_scenario('''
            state.cursorSample(0, 0, 1920, 100);
            check(!state.compact, "another monitor's corner does not reveal");
            state.cursorSample(1920, 100, 1920, 100);
            check(state.compact, "main monitor's corner reveals");
            state.cursorSample(1950, 120, 1920, 100);
            check(state.compact, "hovering where the clock sits reveals it");
            state.cursorSample(1920, 148, 1920, 100);
            check(!state.cornerReveal && !state.hovered, "corner height is 48 logical pixels");
            state.cursorSample(2000, 100, 1920, 100);
            check(!state.cornerReveal && !state.hovered, "corner width is 80 logical pixels");
        ''')

    def test_mouse_motion_clamped_at_screen_edge_keeps_corner_visible(self):
        self.run_scenario('''
            state.cursorSample(100, 100, 0, 0);
            state.idle = false;
            state.cursorSample(0, 0, 0, 0);
            check(state.compact, "screen corner reveals");
            for (let i = 0; i < 20; ++i) {
                state.idle = false;
                state.cursorSample(0, 0, 0, 0);
                check(state.compact, "clamped mouse activity must keep the corner visible");
            }
            state.cursorSample(100, 100, 0, 0);
            check(!state.compact, "leaving still dismisses the corner");
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
            check(state.workspaceReveal && state.compact, "a recent workspace switch can reveal after fullscreen exits");
        ''')

    def test_workspace_reveal_survives_key_release_and_pointer_movement(self):
        self.run_scenario('''
            state.workspaceChanged(3);
            check(state.compact, "workspace reveals");
            state.idle = false;
            check(state.workspaceId === 3, "latest workspace ID is retained");
        ''', later='''
            state.idle = false;
            state.cursorSample(500, 500, 0, 0);
            check(state.workspaceReveal && state.compact, "key release/input cannot cancel the protected linger");
        ''', delay=2000)

    def test_workspace_expiry_allows_collapse_and_fullscreen_cancels_peek(self):
        self.run_scenario('''
            state.lingerDuration = 100;
            state.workspaceChanged(2);
            state.workspaceTransition = true;
        ''', later='''
            check(!state.workspaceReveal && state.compact, "resize transition keeps the surface through collapse");
            state.workspaceTransition = false;
            check(!state.compact, "clock hides after both linger and collapse finish");
            state.workspaceChanged(4);
            state.fullscreen = true;
            check(!state.workspaceReveal && !state.compact, "fullscreen cancels a workspace peek");
            state.fullscreen = false;
            check(!state.compact, "cancelled workspace peek stays hidden");
        ''', delay=250)

    def test_repeated_switches_restart_linger_and_keep_latest_workspace(self):
        self.run_scenario('''
            state.lingerDuration = 350;
            state.workspaceChanged(2);
        ''', later='''
            state.workspaceChanged(4);
            check(state.workspaceId === 4 && state.workspaceReveal, "rapid switching updates icon and restarts the linger");
        ''', delay=200)

    def test_hover_bounds_scale_and_linger_survives_input_but_not_fullscreen(self):
        self.run_scenario('''
            state.hoverBounds = Qt.rect(8, 8, 180, 40);
            state.cursorSample(120, 20, 0, 0);
            check(state.hovered && state.compact, "hover follows a wider clock beyond the corner zone");
            state.cursorSample(300, 200, 0, 0);
            state.idle = false;
            check(!state.hovered && state.hoverLinger && state.compact, "linger timer keeps the clock visible after exit/input");
            state.fullscreen = true;
            check(!state.compact, "fullscreen overrides the lingering outline");
            check(!state.hoverLinger, "fullscreen cancels the linger timer");
            state.fullscreen = false;
            check(!state.compact, "no stale reveal after the outline retracts");
        ''')

    def test_clock_lingers_independently_for_two_and_a_half_seconds(self):
        self.run_scenario('''
            state.cursorSample(30, 20, 0, 0);
            state.cursorSample(200, 200, 0, 0);
            state.idle = false;
            check(state.lingerDuration === 2500, "clock lingers for two and a half seconds");
        ''', later='''
            check(state.hoverLinger && state.compact, "clock stays after the short outline animation has ended");
        ''', delay=2000)

    def test_clock_hides_after_linger_and_reentry_cancels_pending_hide(self):
        self.run_scenario('''
            state.lingerDuration = 100;
            state.cursorSample(30, 20, 0, 0);
            state.cursorSample(200, 200, 0, 0);
        ''', later='''
            check(!state.hoverLinger && !state.compact, "clock hides when linger expires");
            state.cursorSample(30, 20, 0, 0);
            state.cursorSample(200, 200, 0, 0);
            state.cursorSample(30, 20, 0, 0);
            check(state.hovered && !state.hoverLinger && state.compact, "reentry cancels the pending hide");
        ''', delay=250)


class UsageOutlineTests(QmlScenarioTests):
    component_name = "UsageOutline"
    dependencies = ("HoverOutline",)

    def test_load_colors_scale_only_over_the_revealed_straight_segments(self):
        self.run_scenario('''
            state.width=80;state.height=31;state.motionEnabled=false;
            state.cpu=80;state.ram=40;state.hovered=true;
            check(state.progress===1,"usage reuses the hover animation");
            check(Math.abs(state.cpuLength-state.usableStraight*.8)<.001,"top yellow length follows CPU");
            check(Math.abs(state.ramLength-state.usableStraight*.4)<.001,"bottom green length follows RAM");
            state.progress=.05;
            check(state.cpuLength===0&&state.ramLength===0,"colors cannot precede the curve during entry");
            state.progress=1;state.cpu=500;state.ram=-20;
            check(state.cpuLength===state.usableStraight&&state.ramLength===0,"load segments stay inside straight edges");
            state.active=false;check(state.progress===0,"expanded/hidden usage has no outer hover outline");
        ''')


class UsageServiceTests(QmlScenarioTests):
    component_name = "UsageService"

    def test_telemetry_updates_keep_core_identities_and_ignore_incomplete_frames(self):
        self.run_scenario('''
            const frame={cpu:20,cores:[{id:0,percent:10},{id:1,percent:30}],ram:{percent:50},gpu:{},network:{}};
            state.acceptState(JSON.stringify(frame));
            const row=state.coresModel.get(0);
            frame.cpu=40;frame.cores[0].percent=35;state.acceptState(JSON.stringify(frame));
            check(row.key===0&&state.coresModel.count===2,"core delegates retain their identities for number rolling");
            check(state.state.cpu===40&&state.state.cores[0].percent===35,"telemetry values update");
            state.acceptState("not-json");state.acceptState("{}");
            check(state.state.cpu===40,"partial frames retain the last valid sample");
            check(!state.requested,"hidden menu does not launch telemetry");
        ''')


class RollingClockTests(QmlScenarioTests):
    component_name = "RollingClock"

    def test_usage_numbers_share_the_clock_roll_without_a_special_colon_slot(self):
        self.run_scenario('''
            state.active=false;state.clockMode=false;state.fontSize=26;state.timeText=" 17";
            state.active=true;state.timeText=" 18";
            check(state.characterCount===3&&state.digitChanged(2)&&state.rolling,"third numeric character rolls like every other digit");
            check(state.digitDimmed(1)&&!state.digitDimmed(0),"unchanged digits dim but padding stays empty");
        ''', later='''
            check(!state.rolling&&!state.digitDimmed(1)&&state.colonOn,"numbers settle white and never blink");
        ''', delay=600)

    def test_only_changed_digits_roll_and_all_return_white(self):
        self.run_scenario('''
            state.active = false;
            state.timeText = "09:09";
            state.active = true;
            state.timeText = "09:10";
            check(state.rolling, "minute change starts the roll");
            check(state.previousTime === "09:09", "outgoing digits retain old time");
            check(state.displayedTime === "09:10", "incoming digits show new time");
            check(!state.digitChanged(0) && !state.digitChanged(1), "hours stay still");
            check(state.digitChanged(3) && state.digitChanged(4), "changed minutes roll");
            check(state.digitDimmed(0) && state.digitDimmed(1), "unchanged digits grey during roll");
            check(!state.digitDimmed(2) && !state.digitChanged(2), "colon never rolls or greys");
            check(!state.digitDimmed(3) && !state.digitDimmed(4), "rolling digits stay white");
        ''', later='''
            check(!state.rolling && state.progress === 1, "roll finishes");
            for (let i = 0; i < 5; ++i)
                check(!state.digitDimmed(i), "all digits return white after roll");
        ''', delay=450)

    def test_hour_and_midnight_rollovers(self):
        self.run_scenario('''
            state.active = false;
            state.timeText = "09:59";
            state.active = true;
            state.timeText = "10:00";
            for (let i of [0, 1, 3, 4])
                check(state.digitChanged(i), "hour rollover changes all four digits");
            state.active = false;
            state.timeText = "23:59";
            state.active = true;
            state.timeText = "00:00";
            check(state.previousTime === "23:59", "midnight keeps correct outgoing time");
            for (let i of [0, 1, 3, 4])
                check(state.digitChanged(i), "midnight changes all four digits");
        ''')

    def test_hidden_updates_settle_and_reveal_without_stale_rolls(self):
        self.run_scenario('''
            state.timeText = "12:34";
            state.active = false;
            check(!state.rolling && state.progress === 1, "hiding cancels a running roll");
            state.timeText = "12:35";
            check(state.displayedTime === "12:35" && !state.rolling, "hidden time updates instantly");
            check(state.colonOn, "hidden blink is reset");
        ''', later='''
            check(state.colonOn, "colon timer stays stopped while hidden");
            state.active = true;
            check(!state.rolling && state.progress === 1, "revealing does not replay a stale roll");
        ''', delay=600)

    def test_colon_blinks_with_its_layout_slot_intact(self):
        self.run_scenario('''
            state.timeText = "09:03";
            check(state.colonOn, "colon starts on");
        ''', later='''
            check(!state.colonOn, "colon turns off after half a second");
            check(state.implicitWidth > 0 && state.implicitHeight > 0, "blink keeps its layout slot");
        ''', delay=600)

    def test_reduced_motion_disables_roll_and_blink(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.timeText = "12:34";
            state.timeText = "12:35";
            check(!state.rolling && state.progress === 1, "reduced motion updates without rolling");
        ''', later='''
            check(state.colonOn, "reduced motion keeps the colon steady");
        ''', delay=600)

    def test_rapid_time_corrections_restart_from_the_latest_time(self):
        self.run_scenario('''
            state.timeText = "12:34";
            state.timeText = "12:35";
            state.timeText = "12:36";
            check(state.previousTime === "12:35", "rapid correction replaces outgoing time");
            check(state.displayedTime === "12:36", "latest time wins");
            check(state.rolling && state.digitChanged(4), "latest changed digit rolls");
        ''')


class WorkspaceBadgeTests(QmlScenarioTests):
    component_name = "WorkspaceBadge"

    def test_original_icons_fallback_and_customization(self):
        self.run_scenario('''
            state.workspaceId = 1;
            check(state.icon === "", "restored browser workspace icon");
            state.workspaceId = 3;
            check(state.icon === "󰆍", "restored terminal workspace icon");
            state.workspaceId = 999;
            check(state.icon === "", "unmapped workspace has a visible fallback");
            state.icons = ({999: ""});
            check(state.icon === "", "workspace icon map remains editable");
        ''')

    def test_expansion_uses_content_width_and_smooth_progress(self):
        self.run_scenario('''
            state.height = 31;
            check(state.revealWidth === 0, "collapsed badge takes no space");
            state.expanded = true;
        ''', later='''
            check(state.progress > 0 && state.progress < 1, "expansion has intermediate frames");
            check(state.revealWidth > 0 && state.revealWidth < state.expandedWidth,
                "capsule can track the continuously revealed width");
            const progress = state.progress;
            state.expanded = false;
            state.expanded = true;
            check(state.progress === progress, "rapid switches reverse without jumping");
        ''', delay=100)

    def test_reduced_motion_and_hiding_settle_the_badge(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.expanded = true;
            check(state.progress === 1 && state.revealWidth === state.gap + state.iconWidth,
                "full width includes icon and clock spacing");
            state.minimumIconWidth = 24;
            check(state.revealWidth >= state.gap + 24, "larger icons scale the expansion");
            state.active = false;
            check(state.progress === 0 && state.revealWidth === 0, "hidden badge releases its width");
            state.active = true;
            check(state.progress === 1, "active peek restores its badge without motion");
        ''')

    def test_first_reveal_expands_without_rolling_the_icon(self):
        self.run_scenario('''
            state.active = false;
            state.workspaceId = 3;
            state.active = true;
            state.expanded = true;
            check(!state.rolling && state.displayedIcon === state.icon,
                "first switch from hidden displays the new icon without a roll");
        ''', later='''
            check(state.progress > 0 && state.progress < 1, "first reveal is expanding");
            check(!state.rolling, "expansion does not start an icon roll");
        ''', delay=100)

    def test_plain_clock_reveal_does_not_roll_but_next_visible_switch_does(self):
        self.run_scenario('''
            state.workspaceId = 3;
            state.expanded = true;
            check(!state.rolling, "a visible clock without a badge does not roll on first switch");
        ''', later='''
            check(state.progress === 1, "badge is fully visible");
            const oldIcon = state.displayedIcon;
            state.workspaceId = 2;
            check(state.rolling && state.previousIcon === oldIcon
                && state.displayedIcon === state.icon,
                "second switch rolls from the visible icon to the new one");
            check(state.rollProgress === 0, "new icon starts below with zero opacity");
        ''', delay=350)

    def test_visible_icon_roll_progress_and_rapid_switches(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.expanded = true;
            state.motionEnabled = true;
            state.workspaceId = 2;
        ''', later='''
            check(state.rolling && state.rollProgress > 0 && state.rollProgress < 1,
                "roll has intermediate upward and fade frames");
            const oldIcon = state.displayedIcon;
            state.workspaceId = 3;
            check(state.rolling && state.rollProgress === 0
                && state.previousIcon === oldIcon && state.displayedIcon === state.icon,
                "rapid switch rolls from the latest icon, without a stale queued update");
        ''', delay=100)

    def test_icon_roll_finishes_and_identical_icons_do_not_roll(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.expanded = true;
            state.motionEnabled = true;
            state.workspaceId = 7;
        ''', later='''
            check(!state.rolling && state.rollProgress === 1 && state.displayedIcon === state.icon,
                "icon finishes fully opaque at its resting position");
            state.workspaceId = 8;
            check(!state.rolling, "workspaces with the same glyph need no roll");
        ''', delay=350)

    def test_hidden_and_reduced_motion_updates_settle_without_replay(self):
        self.run_scenario('''
            state.motionEnabled = false;
            state.expanded = true;
            state.motionEnabled = true;
            state.workspaceId = 2;
            check(state.rolling, "visible switch starts rolling");
            state.active = false;
            check(!state.rolling && state.rollProgress === 1, "hiding cancels the roll");
            state.workspaceId = 3;
            state.active = true;
            check(!state.rolling && state.displayedIcon === state.icon,
                "hidden updates reveal the latest icon without replay");
            state.motionEnabled = false;
            state.workspaceId = 4;
            check(!state.rolling && state.rollProgress === 1 && state.displayedIcon === state.icon,
                "reduced motion changes icons immediately");
            state.motionEnabled = true;
            state.workspaceId = 5;
            check(state.rolling, "normal motion can resume");
            state.motionEnabled = false;
            check(!state.rolling && state.rollProgress === 1,
                "enabling reduced motion during a roll settles it");
        ''')


class HoverOutlineTests(QmlScenarioTests):
    component_name = "HoverOutline"

    def test_outline_is_inset_closed_and_scales_with_its_container(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.motionEnabled = false;
            state.hovered = true;
            check(state.progress === 1, "hover completes the outline");
            check(state.edgeInset - state.strokeWidth / 2 > 0, "background remains outside the stroke");
            check(state.trimStart === 0, "upper and lower strokes meet at the leftmost point");
            check(state.trimEnd === 1, "upper and lower strokes also meet at the rightmost point");
            const originalLength = state.halfLength;
            state.width = 200; state.height = 48;
            check(state.halfLength > originalLength && state.radius > 0, "geometry follows a larger capsule");
            check(state.trimStart === 0 && state.trimEnd === 1, "resized outline stays fully closed");
            check(state.radius <= state.innerHeight / 2 && state.radius <= state.innerWidth / 2,
                "curves stay inside their inset bounds");
            state.hovered = false;
            check(state.progress === 0, "reduced motion removes the stroke immediately");
        ''')

    def test_outline_exit_is_quick_and_independent_of_clock_linger(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.motionEnabled = false; state.hovered = true;
            state.motionEnabled = true; state.hovered = false;
            check(state.enterDuration === 300 && state.exitDuration === 220, "outline timings stay short");
        ''', later='''
            check(state.progress === 0 && !state.animating, "outline is gone long before the clock's linger expires");
        ''', delay=400)

    def test_exit_completes_without_a_remaining_stroke(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.motionEnabled = false; state.hovered = true;
            state.motionEnabled = true; state.exitDuration = 100;
            state.hovered = false;
        ''', later='''
            check(state.progress === 0 && !state.animating, "retraction leaves no remaining stroke");
        ''', delay=250)

    def test_reentry_reverses_from_current_progress_without_jumping(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.hovered = true;
        ''', later='''
            const progress = state.progress;
            check(progress > 0 && progress < 1, "entry is in progress");
            state.hovered = false;
            check(state.progress === progress, "exit starts from current progress");
            state.hovered = true;
            check(state.progress === progress, "reentry preserves current progress");
        ''', delay=100)

    def test_hiding_or_reduced_motion_settles_the_effect(self):
        self.run_scenario('''
            state.width = 58; state.height = 31;
            state.hovered = true; state.motionEnabled = false;
            check(state.progress === 1, "reduced motion settles at the hovered state");
            state.active = false;
            check(state.progress === 0 && !state.animating, "hiding cancels the drawing animation");
            state.active = true;
            check(state.progress === 1, "active hover restores the outline without motion");
        ''')


if __name__ == "__main__":
    unittest.main()

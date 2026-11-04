"""AI panel: remaining-limit parsing, T3 server detection and panel states.

Nothing here contacts Anthropic, starts T3 or signals a real process.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import types
import unittest
import urllib.error
from unittest.mock import patch

from test_quickshell_visibility import QmlScenarioTests


class AiBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / 'home-modules/quickshell.nix'
        expression = (f'let m=import {json.dumps(str(path))} {{pkgs.writeText = name: text: text;}};'
            'in m.xdg.configFile."quickshell/AiBackend.py".source')
        source = subprocess.check_output(['nix', 'eval', '--impure', '--raw', '--expr', expression], text=True)
        cls.backend = types.ModuleType('ai_backend_test')
        exec(compile(source, 'AiBackend.py', 'exec'), cls.backend.__dict__)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ai-backend-test-')
        self.root = Path(self.temp.name)
        self.now = 1_800_000_000.0

    def tearDown(self):
        self.temp.cleanup()

    def test_windows_report_remaining_and_roll_over_after_reset(self):
        now_ms = int(self.now * 1000)
        self.assertEqual(self.backend.window('5-hour', 14, now_ms + 1000, now_ms)['remaining'], 86)
        self.assertEqual(self.backend.window('5-hour', 140, None, now_ms)['remaining'], 0, 'overuse is clamped')
        rolled = self.backend.window('Weekly', 90, now_ms - 1, now_ms)
        self.assertEqual((rolled['remaining'], rolled['resetsAt']), (100, None), 'an expired window is full again')
        self.assertIsNone(self.backend.window('5-hour', None, None, now_ms)['remaining'])

    def write_rollout(self, name, lines, mtime):
        path = self.root / 'sessions/2026/11/03' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('\n'.join(json.dumps(line) for line in lines) + '\n')
        os.utime(path, (mtime, mtime))

    def test_codex_uses_newest_snapshot_sorted_shortest_window_first(self):
        def event(primary, secondary, stamp='2026-11-03T10:00:00Z'):
            return {'timestamp': stamp, 'type': 'event_msg', 'payload': {'type': 'token_count', 'rate_limits': {
                'primary': primary, 'secondary': secondary, 'plan_type': 'plus'}}}
        later = int(self.now) + 3600
        self.write_rollout('rollout-old.jsonl', [event({'used_percent': 50, 'window_minutes': 300, 'resets_at': later}, None)], self.now - 100)
        self.write_rollout('rollout-new.jsonl', [
            event({'used_percent': 1, 'window_minutes': 300, 'resets_at': later}, None),
            event({'used_percent': 67, 'window_minutes': 10080, 'resets_at': later},
                {'used_percent': 7, 'window_minutes': 300, 'resets_at': later}),
            {'type': 'event_msg', 'payload': {'type': 'agent_message'}}], self.now - 10)
        entry = self.backend.codex_state(self.now, root=self.root)
        self.assertEqual(entry['plan'], 'Plus')
        self.assertEqual([(w['label'], w['remaining']) for w in entry['windows']], [('5-hour', 93), ('Weekly', 33)])
        empty = self.backend.codex_state(self.now, root=self.root / 'missing')
        self.assertEqual((empty['windows'], bool(empty['error'])), ([], True))

    def claude(self, fetch, expires=None, cached=None):
        credentials = self.root / 'credentials.json'
        credentials.write_text(json.dumps({'claudeAiOauth': {'accessToken': 'secret-token', 'subscriptionType': 'pro',
            'expiresAt': expires if expires is not None else int(self.now * 1000) + 3_600_000}}))
        cache = self.root / 'cache.json'
        if cached is not None:
            cache.write_text(json.dumps(cached))
        return self.backend.claude_state(self.now, fetch=fetch, credentials=credentials, cache=cache), cache

    def test_claude_parses_usage_caches_privately_and_spares_the_api(self):
        payload = {'five_hour': {'utilization': 14.0, 'resets_at': '2027-01-16T08:00:00+00:00'},
            'seven_day': {'utilization': 2.0, 'resets_at': '2027-01-20T12:00:00+00:00'}}
        calls = []
        entry, cache = self.claude(lambda token: calls.append(token) or payload)
        self.assertEqual(calls, ['secret-token'])
        self.assertEqual(entry['plan'], 'Pro')
        self.assertEqual([(w['label'], w['remaining']) for w in entry['windows']], [('5-hour', 86), ('Weekly', 98)])
        self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('secret-token', cache.read_text())
        entry, _ = self.claude(lambda token: self.fail('a fresh cache must not call the API'),
            cached={'fetched': self.now - 30, 'payload': payload})
        self.assertEqual(entry['windows'][0]['remaining'], 86)

    def test_claude_errors_keep_last_numbers_and_never_send_expired_tokens(self):
        stale = {'fetched': self.now - 600, 'payload': {'five_hour': {'utilization': 40.0}}}
        entry, _ = self.claude(lambda token: self.fail('expired tokens are not sent'),
            expires=int(self.now * 1000) - 1, cached=stale)
        self.assertIn('refresh', entry['error'])
        self.assertEqual(entry['windows'][0]['remaining'], 60, 'last known numbers stay visible')
        def limited(token):
            raise urllib.error.HTTPError('https://api.anthropic.com', 429, 'Too many', {}, None)
        entry, _ = self.claude(limited, cached=stale)
        self.assertEqual(entry['error'], 'Usage is rate limited')
        (self.root / 'cache.json').unlink()
        entry, _ = self.claude(lambda token: ['not', 'a', 'dict'])
        self.assertEqual((entry['error'], entry['windows']), ('Usage unavailable', []))

    def test_missing_cli_is_left_out_of_the_panel(self):
        with patch.object(self.backend, 'installed', side_effect=lambda name: name == 'codex'), \
                patch.object(self.backend, 'codex_state', return_value={'id': 'codex'}), \
                patch.object(self.backend, 'claude_state', side_effect=AssertionError('claude is not installed')), \
                patch.object(self.backend, 't3_state', return_value={'state': 'stopped'}), \
                patch('sys.argv', ['AiBackend.py']), patch('builtins.print') as output:
            self.backend.main()
        state = json.loads(output.call_args.args[0])
        self.assertEqual([p['id'] for p in state['providers']], ['codex'])

    def test_t3_state_requires_a_live_runtime_pid(self):
        userdata = self.root / 'userdata'
        userdata.mkdir()
        with patch.object(self.backend, 'unit_state', return_value='inactive'):
            self.assertEqual(self.backend.t3_state('systemctl', base=self.root)['state'], 'stopped')
            (userdata / 'server-runtime.json').write_text(json.dumps({'pid': os.getpid(), 'port': 3773,
                'origin': 'http://127.0.0.1:3773', 'serverVersion': '0.1.7-nightly.20261103.4119'}))
            running = self.backend.t3_state('systemctl', base=self.root)
            self.assertEqual((running['state'], running['port'], running['managed']), ('running', 3773, False))
            (userdata / 'server-runtime.json').write_text(json.dumps({'pid': 2 ** 22 + 12345}))
            self.assertEqual(self.backend.t3_state('systemctl', base=self.root)['state'], 'stopped', 'dead pid')
        with patch.object(self.backend, 'unit_state', return_value='activating'):
            self.assertEqual(self.backend.t3_state('systemctl', base=self.root)['state'], 'starting')

    def test_stop_refuses_to_signal_a_process_that_is_not_t3_serve(self):
        args = types.SimpleNamespace(systemctl='systemctl')
        with patch.object(self.backend, 'unit_state', return_value='inactive'), \
                patch.object(self.backend, 't3_runtime', return_value={'pid': os.getpid()}), \
                patch.object(self.backend.os, 'kill') as kill:
            with self.assertRaises(RuntimeError):
                self.backend.stop(args)
            kill.assert_not_called()

    def test_pairing_link_is_parsed_from_cli_output(self):
        output = 'Pairing with nixos.\nPairing URL: http://localhost:3773/pair#token=ABC123\nToken: ABC123\n'
        result = types.SimpleNamespace(stdout=output)
        with patch.object(self.backend.subprocess, 'run', return_value=result) as run:
            url = self.backend.pair(types.SimpleNamespace(steam_run='steam-run', npx='npx'), {})
        self.assertEqual(url, 'http://localhost:3773/pair#token=ABC123')
        self.assertIn('pair', run.call_args.args[0])


class AiServiceTests(QmlScenarioTests):
    component_name = 'AiService'

    def test_frames_actions_and_browser_urls_are_validated(self):
        self.run_scenario('''
            state.acceptState('{"providers":[{"id":"claude"}],"t3":{"state":"running"}}');
            check(state.providers.length===1 && state.t3State==="running","complete frames apply");
            state.acceptState('{"providers":"bad","t3":{}}');state.acceptState("garbage");
            check(state.providers.length===1,"malformed frames keep the last state");
            state.pending="stop";check(state.t3State==="stopping" && state.busy,"local intent shows immediately");
            state.pending="";
            const opened=[];state.browserRequested.connect(url=>opened.push(url));
            state.acceptAction('{"ok":true,"url":"http://localhost:3773/pair#token=abc","error":""}');
            state.acceptAction('{"ok":true,"url":"https://example.com/","error":""}');
            state.acceptAction('{"ok":true,"url":"javascript:alert(1)","error":""}');
            check(opened.length===1 && opened[0].startsWith("http://localhost:3773/"),"only the local T3 server opens");
            state.acceptAction('{"ok":false,"url":"","error":"T3 did not start in time"}');
            check(state.error==="T3 did not start in time","action errors surface");
        ''')


class AiDetailsTests(QmlScenarioTests):
    component_name = 'AiDetails'
    dependencies = ('FrostedSurface', 'HoverOutline', 'MediaButton', 'UsageValue', 'RollingClock', 'T3SkyButton')

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.controller = cls.controller.replace('required property var ai', '''property var actions: []
    property var ai: QtObject {
        property var state: ({providers:[],t3:{state:"stopped",origin:"",version:"",managed:false}})
        readonly property var providers: state.providers
        property string pending: ""
        readonly property string t3State: pending==="start" ? "starting" : state.t3.state
        readonly property bool busy: pending!==""
        property string error: ""
        function start(){details.actions.push("start");}
        function stop(){details.actions.push("stop");}
        function openT3(){details.actions.push("open");}
    }''')

    def test_t3_button_morphs_and_cards_follow_installed_clis(self):
        self.run_scenario('''
            function find(item,name){if(item.objectName===name)return item;for(const child of item.children || []){const r=find(child,name);if(r)return r;}return null;}
            state.motionEnabled=false;
            const card=find(state,"t3Card");
            check(card.x===20 && card.width===560,"without CLIs the T3 card takes the panel");
            const start=find(state,"startT3");
            check(!!start && !find(state,"stopT3").visible,"stopped: one start button");
            start.clicked();check(state.actions.join()==="start","start launches the server");
            state.ai.pending="start";check(!start.enabled && start.caption==="Starting…","starting disables the button");
            state.ai.pending="";
            state.ai.state=({providers:[{id:"claude",name:"Claude",plan:"Pro",error:"",updatedAt:null,
                windows:[{label:"5-hour",remaining:86,resetsAt:null},{label:"Weekly",remaining:9,resetsAt:null}]}],
                t3:{state:"running",origin:"http://127.0.0.1:3773",port:3773,version:"0.1.7-nightly.20261103.4119",managed:true}});
        ''', later='''
            function find(item,name){if(item.objectName===name)return item;for(const child of item.children || []){const r=find(child,name);if(r)return r;}return null;}
            check(find(state,"t3Card").x===372,"installed CLIs take the left column");
            check(find(state,"aiRemaining-claude-0").text==="86","remaining share, not usage, is shown");
            const open=find(state,"openT3"),stop=find(state,"stopT3");
            check(!!open && stop.visible && stop.enabled,"running: open and stop");
            open.clicked();stop.clicked();
            check(state.actions.join()==="start,open,stop","each button routes its own action");
            check(state.t3Version==="Nightly 2026-11-03","nightly build date is shown");
        ''')


if __name__ == '__main__':
    unittest.main()

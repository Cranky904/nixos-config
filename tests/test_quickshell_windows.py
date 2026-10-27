"""Window statistics, lifetimes and controls without changing desktop applications."""
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

from test_quickshell_visibility import QmlScenarioTests


class WindowBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1]/'home-modules/quickshell.nix'
        expression = f'let m=import {json.dumps(str(path))} {{pkgs.writeText = name: text: text;}};in m.xdg.configFile."quickshell/WindowBackend.py".source'
        source = subprocess.check_output(['nix','eval','--impure','--raw','--expr',expression],text=True)
        cls.backend = types.ModuleType('window_backend_test')
        exec(compile(source,'WindowBackend.py','exec'),cls.backend.__dict__)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='window-backend-')
        self.root = Path(self.temp.name)
        self.collector = self.backend.Collector(self.root, cpu_count=4, ticks=100)
        self.write('meminfo','MemTotal: 1000 kB')

    def tearDown(self):
        self.temp.cleanup()

    def write(self,path,text):
        dest=self.root/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(text)

    def process(self,pid,parent,ticks,start=10,pss=100):
        fields=['S',str(parent)]+['0']*18
        fields[11],fields[12],fields[19]=str(ticks),'0',str(start)
        self.write(f'{pid}/stat',f'{pid} (name with ) spaces) '+ ' '.join(fields))
        self.write(f'{pid}/smaps_rollup',f'Rss: 300 kB\nPss: {pss} kB\nPss_Anon: 10 kB')

    def test_descendants_cpu_share_and_proportional_memory(self):
        self.process(10,1,100,pss=100)
        self.process(11,10,50,pss=50)
        self.process(12,11,20,pss=20)
        self.process(99,1,10000,pss=900)
        with patch.object(self.collector,'gpu',return_value={11:7,12:3,99:90}):
            first=self.collector.sample('window',10,now=10)
            self.assertIsNone(first['cpu'])
            self.assertEqual(first['pids'],[10,11,12])
            self.assertEqual(first['ram'],17)
            self.assertEqual(first['gpu'],10)
            self.process(10,1,140,pss=100)
            self.process(11,10,90,pss=50)
            self.assertEqual(self.collector.sample('window',10,now=12)['cpu'],10)

    def test_pid_reuse_and_window_switch_never_inherit_cpu_ticks(self):
        self.process(10,1,100)
        with patch.object(self.collector,'gpu',return_value={}):
            self.collector.sample('first',10,now=1)
            self.process(10,1,10000,start=99)
            self.assertEqual(self.collector.sample('first',10,now=2)['cpu'],0)
            self.assertIsNone(self.collector.sample('second',10,now=3)['cpu'])
            self.assertIsNone(self.collector.sample('gone',123456,now=4)['ram'])

    def test_restricted_pss_uses_rss_and_unsupported_gpu_is_unknown(self):
        self.process(10,1,0)
        self.write('10/smaps_rollup','')
        self.write('10/status','VmRSS: 50 kB')
        with patch.object(self.collector,'gpu',return_value={10:None}):
            state=self.collector.sample('window',10,now=1)
        self.assertEqual(state['ram'],5)
        self.assertIsNone(state['gpu'])
        rows=self.backend.gpu_processes('# gpu pid type sm mem\n0 10 G 25 7\n0 11 G - -\n0 - - - -')
        self.assertEqual(rows,{10:25,11:None})
        self.assertIsNone(self.backend.gpu_processes('NVIDIA driver unavailable'))
        with patch.object(self.backend.subprocess,'run',side_effect=subprocess.TimeoutExpired('nvidia-smi',1.5)):
            self.assertIsNone(self.collector.gpu())

    def test_window_lifetime_survives_focus_changes_restart_and_empty_startup(self):
        path=self.root/'runtime/times.json'
        times=self.backend.Lifetimes(path,'session-one')
        self.assertEqual(times.update([{'key':'a','born':1000}],now=2000)['a'],1000)
        times.update([{'key':'a','born':9000},{'key':'b','born':2500}],now=10000)
        restarted=self.backend.Lifetimes(path,'session-one')
        restarted.update([],now=11000)
        self.assertEqual(restarted.update([{'key':'a','born':11000}],now=12000)['a'],1000)
        self.assertEqual(path.stat().st_mode & 0o777,0o600)
        self.assertEqual(self.backend.Lifetimes(path,'different-session').births,{})

    def test_icons_resolve_theme_files_and_fall_back_to_hicolor(self):
        self.write('icons/theme/scalable/apps/browser.svg','<svg/>')
        self.write('icons/hicolor/128x128/apps/terminal.png','png')
        resolver=self.backend.IconResolver([self.root/'icons'],'theme')
        self.assertTrue(resolver.resolve('browser').endswith('/theme/scalable/apps/browser.svg'))
        self.assertTrue(resolver.resolve('terminal').endswith('/hicolor/128x128/apps/terminal.png'))
        self.assertEqual(resolver.resolve('../private'),'')
        self.assertEqual(resolver.resolve('missing'),'')


class WindowServiceTests(QmlScenarioTests):
    component_name='WindowService'

    def test_recent_focus_order_lifetimes_and_desktop_on_empty_workspace(self):
        self.run_scenario('''
            state.requested=false;
            state.workspace=1;
            state.clients=[{address:"0xa",pid:11,stableId:"one",class:"kitty",title:"First",workspace:{id:1},focusHistoryID:0},
                {address:"0xb",pid:12,stableId:"two",class:"kitty",title:"Second",workspace:{id:1},focusHistoryID:1}];
            state.focused=state.clients[0];state.refresh();
            const born=state.current.born;
            check(state.current.address==="0xa","select active window");
            check(state.recent[0].address==="0xb","seed recent windows from compositor focus order");
            state.focused=state.clients[1];state.refresh();
            check(state.recent[0].address==="0xa","previous window becomes most recent");
            state.focused=state.clients[0];state.refresh();
            check(state.current.born===born,"focus does not reset window lifetime");
            state.focused=null;state.refresh();
            check(!state.desktop,"menu keyboard focus preserves underlying window");
            state.workspace=2;state.refresh();
            check(state.desktop,"empty workspace uses desktop stats");
        ''')

    def test_window_actions_validate_live_addresses_and_stale_stats_are_ignored(self):
        self.run_scenario('''
            state.requested=false;state.workspace=1;
            state.clients=[{address:"0xa",pid:11,class:"kitty",workspace:{id:1}}];
            state.focused=state.clients[0];state.refresh();
            const commands=[];state.dispatchRequested.connect(command=>commands.push(command));
            state.focusWindow("0xa");state.closeWindow();
            state.focusWindow("0xa; quit");state.focusWindow("0xb");
            check(commands.join("|")==="focuswindow address:0xa|closewindow address:0xa","only live validated addresses dispatch");
            state.acceptState(JSON.stringify({key:state.current.key,pids:[11,12],births:{},cpu:2,ram:3,gpu:null}));
            check(state.pids.length===2,"current process descendants available for audio matching");
            state.acceptState(JSON.stringify({key:"old",pids:[99],births:{},cpu:80,ram:80,gpu:80}));
            check(state.pids.length===0,"old frame cannot match another app audio");
            state.clients=[];state.focused=null;state.refresh();state.closeWindow();
            check(commands.length===2,"desktop close is harmless");
        ''')

    def test_layer_focus_recovers_other_workspace_and_shared_process_windows_keep_identity(self):
        self.run_scenario('''
            state.requested=false;state.workspace=1;
            state.clients=[{address:"0xa",pid:11,stableId:"first",class:"chromium",workspace:{id:1},focusHistoryID:0},
                {address:"0xb",pid:11,stableId:"second",class:"chromium",workspace:{id:2},focusHistoryID:1}];
            state.focused=state.clients[0];state.refresh();
            const firstKey=state.current.key;
            state.focused=null;state.workspace=2;state.refresh();
            check(state.current.address==="0xb","layer focus on populated workspace must not show desktop");
            check(state.current.key!==firstKey,"browser windows sharing a PID have separate lifetimes");
            const secondKey=state.current.key;
            state.clients=[{address:"0xb",pid:11,stableId:"replacement",class:"chromium",workspace:{id:2}}];
            state.refresh();
            check(state.current.key!==secondKey,"reused window address does not inherit old identity");
        ''')


class WindowAudioTests(QmlScenarioTests):
    component_name='WindowAudio'

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Supply required context before construction; production keeps real required properties.
        cls.controller=cls.controller.replace('required property var window',
            'property var window: QtObject {property bool desktop:false;property var current: ({pid:10,className:"chromium-browser"});property var pids:[10,11]}')
        cls.controller=cls.controller.replace('required property var master',
            'property var master: QtObject {property bool available:true;property real volume:0.4;property bool muted:false;property var bands:[];function setVolume(v){volume=v;}}')

    def test_application_match_scroll_clamp_and_mute_preservation(self):
        self.run_scenario('''
            function node(pid,name,volume) {
                const n=Qt.createQmlObject('import QtQuick; QtObject {property bool ready:true;property var properties:({});property QtObject audio:QtObject{property real volume:0;property bool muted:true}}',state);
                n.properties={"application.process.id":pid,"application.name":name};n.audio.volume=volume;return n;
            }
            const own=node(11,"Chromium",0.5),other=node(99,"Chromium",0.8);
            check(state.matches(own),"descendant audio process belongs to window");
            check(!state.matches(other),"a different known PID cannot match by name");
            check(state.matches(node(0,"Chromium",0.4)),"missing PID can use application identity");
            state.candidates=[own,other];state.active=true;
            check(state.available && state.matched.length===1,"only selected application is controlled");
            state.scroll(60);check(own.audio.volume===0.5,"half notch waits");
            state.scroll(60);check(Math.abs(own.audio.volume-0.55)<0.0001,"scroll adds five points");
            check(other.audio.volume===0.8 && own.audio.muted,"other streams and mute remain intact");
            state.setVolume(8);check(own.audio.volume===1,"clamp stream volume");
            state.window.desktop=true;state.setVolume(0.3);
            check(state.master.volume===0.3 && own.audio.volume===1,"desktop alone controls master");
        ''')


if __name__=='__main__':
    unittest.main()

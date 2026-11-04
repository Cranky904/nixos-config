"""Network fixtures and UI state checks; never change the machine's connectivity."""
import getpass
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

from test_quickshell_visibility import QmlScenarioTests


class NetworkBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module=Path(__file__).resolve().parents[1]/'home-modules/quickshell.nix'
        source=subprocess.check_output(['nix','eval','--impure','--raw','--expr',
            f'let m=import {json.dumps(str(module))} {{pkgs.writeText = name: text: text;}};in m.xdg.configFile."quickshell/NetworkBackend.py".source'],text=True)
        cls.backend=types.ModuleType('network_test')
        exec(compile(source,'NetworkBackend.py','exec'),cls.backend.__dict__)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='quickshell-network-')
        self.root=Path(self.temp.name)
        self.commands=[]
        self.raw={'BackendState':'Running','TailscaleIPs':['100.64.0.1'], 'Self':{'HostName':'desktop'},'Peer':{
            'b':{'ID':'b','HostName':'laptop','OS':'linux','TailscaleIPs':['100.64.0.2'],'Online':True,'ExitNodeOption':True},
            'a':{'ID':'a','HostName':'phone','OS':'android','TailscaleIPs':['100.64.0.3'],'Online':False,'ExitNodeOption':True}}}
        self.operator=True
        self.fail=False
        self.collector=self.backend.Backend('fixture-nmcli','fixture-tailscale',self.root/'proc',self.root/'sys',self.run_command)
        self.write('proc/net/route','Iface Destination Gateway Flags RefCnt Use Metric Mask\nwlan0 00000000 0101A8C0 0003 0 0 600 00000000\neth0 00000000 0101A8C0 0003 0 0 100 00000000')
        self.write('sys/class/net/eth0/speed','1000')
        self.write('sys/class/net/eth0/statistics/rx_bytes','2048')
        self.write('sys/class/net/eth0/statistics/tx_bytes','512')

    def tearDown(self):self.temp.cleanup()

    def write(self,name,text):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)

    def run_command(self,command,**kwargs):
        self.commands.append(command)
        output=''
        if self.fail:return subprocess.CompletedProcess(command,1,'','unavailable')
        if command[0]=='fixture-nmcli':
            if command[-2:]==['device','status']:
                output='tailscale0:tun:connected:tailscale0\nwlan0:wifi:connected:Wireless\neth0:ethernet:connected:Wired\\: Office\n'
            elif command[-3:]==['device','show','eth0']:
                output='GENERAL.STATE:100 (connected)\nIP4.ADDRESS[1]:192.168.1.2/24\nIP4.GATEWAY:192.168.1.1\nIP4.DNS[1]:192.168.1.1\nIP4.DNS[2]:1.1.1.1\n'
            elif command[-2:]==['general','status']:output='full\n'
        elif command[-2:]==['status','--json']:output=json.dumps(self.raw)
        elif command[-2:]==['debug','prefs']:output=json.dumps({'OperatorUser':getpass.getuser() if self.operator else ''})
        return subprocess.CompletedProcess(command,0,output,'')

    def test_primary_connection_details_and_counters_exclude_virtual_devices(self):
        state=self.collector.network()
        self.assertEqual(state['interface'],'eth0')
        self.assertEqual(state['name'],'Wired: Office')
        self.assertEqual(state['address'],'192.168.1.2')
        self.assertEqual(state['dns'],['192.168.1.1','1.1.1.1'])
        self.assertEqual((state['received'],state['sent'],state['speed']),(2048,512,1000))
        self.assertEqual(state['state'],'Connected')
        self.assertFalse(any('check' in c or '--rescan' in c for c in self.commands))

    def test_tailscale_status_sorts_online_peers_and_handles_missing_data(self):
        state=self.collector.tails()
        self.assertTrue(state['running'])
        self.assertEqual(state['ip'],'100.64.0.1')
        self.assertEqual([p['key'] for p in state['peers']],['b','a'])
        self.assertEqual(self.backend.tail_state(None)['status'],'Unavailable')
        self.assertEqual(self.backend.ipv4(['fd7a::1','invalid','100.64.0.2']),'100.64.0.2')

    def test_exit_selection_is_validated_and_preserves_other_preferences(self):
        with patch.object(self.backend.os,'geteuid',return_value=1000):
            self.assertEqual(self.collector.action('exit','100.64.0.2'),{'error':''})
            self.assertEqual(self.commands[-1],['fixture-tailscale','set','--exit-node=100.64.0.2'])
            count=len([c for c in self.commands if 'set' in c])
            self.assertTrue(self.collector.action('exit','100.64.0.3')['error'])
            self.assertTrue(self.collector.action('exit','--reset')['error'])
            self.assertEqual(len([c for c in self.commands if 'set' in c]),count)
            self.collector.action('exit','')
            self.assertEqual(self.commands[-1],['fixture-tailscale','set','--exit-node='])
            self.assertFalse(any('--reset' in c for c in self.commands))

    def test_no_operator_requests_one_authenticated_terminal_command_without_writing(self):
        self.operator=False
        with patch.object(self.backend.os,'geteuid',return_value=1000):
            result=self.collector.action('disconnect')
        self.assertEqual(result['terminal'],['sudo','fixture-tailscale','down'])
        self.assertFalse(any('down' in c or 'set' in c for c in self.commands))

    def test_unavailable_services_and_timeouts_are_explicit(self):
        self.fail=True
        state=self.collector.sample()
        self.assertEqual(state['network']['state'],'Unavailable')
        self.assertFalse(state['tailscale']['available'])
        self.assertTrue(self.collector.action('connect')['error'])
        with patch.object(self.collector,'runner',side_effect=subprocess.TimeoutExpired('fixture',1)):
            self.assertFalse(self.collector.tails()['available'])

    def test_escaped_connection_fields_and_indexed_ip_properties(self):
        self.assertEqual(self.backend.split_fields(r'eth0:ethernet:connected:Name\: desk\\room'),['eth0','ethernet','connected','Name: desk\\room'])
        self.assertEqual(self.backend.device_info('IP4.DNS[1]:1.1.1.1\nIP4.DNS[2]:8.8.8.8')['IP4.DNS'],['1.1.1.1','8.8.8.8'])


class NetworkServiceTests(QmlScenarioTests):
    component_name='NetworkService'

    def test_peer_rows_remain_stable_and_clipboard_does_not_launch_network_actions(self):
        self.run_scenario('''
            let copied="";let launched=0;
            state.copyRequested.connect(value=>copied=value);
            state.commandRequested.connect(command=>launched++);
            state.acceptState(JSON.stringify({network:{},tailscale:{peers:[{key:"a",name:"First",online:true}]}}));
            check(state.peersModel.count===1,"peer row created");
            state.acceptState(JSON.stringify({network:{},tailscale:{peers:[{key:"a",name:"Updated",online:false}]}}));
            check(state.peersModel.count===1 && state.state.tailscale.peers[0].name==="Updated","same peer identity keeps the row");
            state.copy("100.64.0.2","a");
            check(copied==="100.64.0.2" && state.copied==="a","copy feedback");
            check(launched===0,"copy never opens a command window");
            state.acceptState("invalid");
            check(state.peersModel.count===1,"invalid frames preserve state");
        ''')

    def test_editor_command_and_network_module_selection(self):
        self.run_scenario('''
            let command=[];state.commandRequested.connect(value=>command=value);
            state.manageNetworks();
            check(command.length===1 && command[0].endsWith("/bin/nm-connection-editor"),"launch the existing connection editor");
            state.action("unknown","");check(!state.busy,"unknown actions ignored");
        ''')


class NetworkSelectionTests(QmlScenarioTests):
    component_name='ExpandedState'

    def test_network_selects_and_retracts_like_existing_modules(self):
        self.run_scenario('''
            state.motionEnabled=false;state.openWith("");
            state.select("network");check(state.selected==="network","network is a valid module");
            state.select("media");check(state.selected==="media","another module replaces network");
            state.select("network");state.select("network");
            check(state.selected==="" && state.open,"second press retracts only the widget");
        ''')


class NetworkDetailsTests(QmlScenarioTests):
    component_name='NetworkDetails'
    dependencies=('FrostedSurface','MediaButton','HoverOutline','PlaylistScrollBar','MediaMorphPanel','UsageValue','RollingClock')

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.controller=cls.controller.replace('required property var network','''property var retainedDown:null
    property var network: QtObject {
        property var state:({network:{},tailscale:{available:true,running:true,status:"Running",peers:[],exitNode:""}})
        property var peersModel:[]
        property var exitsModel:[{key:"direct"}]
        property bool busy:false
        property string error:""
        property string copied:""
        function action(kind,target){}
        function copy(value,key){copied=key;}
        function manageNetworks(){}
    }''').replace('required property var usage', 'property var usage:QtObject {property var state:({network:{download:1024,upload:0}})}')

    def test_rate_changes_keep_existing_rolling_number_instances(self):
        self.run_scenario('''
            function find(item,name){if(item.objectName===name)return item;for(const child of item.children || []){const result=find(child,name);if(result)return result;}return null;}
            state.motionEnabled=false;state.active=true;
            state.retainedDown=find(state,"networkDownload");
            check(!!state.retainedDown,"download value exists");
            state.usage.state=({network:{download:5120,upload:2048}});
        ''',later='''
            function find(item,name){if(item.objectName===name)return item;for(const child of item.children || []){const result=find(child,name);if(result)return result;}return null;}
            check(state.retainedDown===find(state,"networkDownload"),"telemetry updates preserve the number animator");
            check(state.retainedDown.text==="5.0","rate updates in place");
            check(state.rate(null).text==="—","missing data is explicit");
        ''')

    def test_exit_picker_closes_on_outside_click_and_panel_close(self):
        self.run_scenario('''
            state.motionEnabled=false;state.active=true;
            state.choosingExit=true;
        ''',later='''
            state.dismissAt(5,5);check(!state.choosingExit,"outside click dismisses picker");
            state.choosingExit=true;state.active=false;
            check(!state.choosingExit,"closing panel dismisses picker");
        ''')

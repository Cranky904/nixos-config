"""Telemetry calculations against small proc/sys fixtures; never change hardware state."""
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch


class UsageBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / 'home-modules/quickshell.nix'
        expression = f'let m=import {json.dumps(str(path))} {{pkgs.writeText = name: text: text;}};in m.xdg.configFile."quickshell/UsageBackend.py".source'
        source = subprocess.check_output(['nix','eval','--impure','--raw','--expr',expression],text=True)
        cls.backend = types.ModuleType('usage_backend_test')
        exec(compile(source,'UsageBackend.py','exec'),cls.backend.__dict__)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='usage-backend-test-')
        self.root = Path(self.temp.name)
        self.proc, self.sysfs = self.root/'proc', self.root/'sys'
        self.write('proc/cpuinfo','model name : Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz')
        self.write('proc/meminfo','MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 400 kB\nCached: 300 kB')
        self.write('sys/class/net/eth0/operstate','up')
        (self.sysfs/'class/net/eth0/device').mkdir()
        self.write('sys/class/net/tailscale0/operstate','unknown')
        self.collector = self.backend.Collector(self.proc,self.sysfs,'/unused-nvidia-smi')

    def tearDown(self):
        self.temp.cleanup()

    def write(self,path,text):
        target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)

    def test_cpu_deltas_ignore_guest_double_count_and_report_each_core(self):
        old='cpu 100 0 40 800 60 0 0 0 50 0\ncpu0 50 0 20 400 30 0 0 0\ncpu1 50 0 20 400 30 0 0 0'
        new='cpu 140 0 60 870 130 0 0 0 80 0\ncpu0 80 0 40 430 50 0 0 0\ncpu1 60 0 20 440 80 0 0 0'
        self.write('proc/stat',old)
        first=self.collector.sample(now=10)
        self.assertIsNone(first['cpu'],'a first sample has no interval to measure')
        self.write('proc/stat',new)
        second=self.collector.sample(now=12)
        self.assertEqual(second['cpu'],30)
        self.assertEqual([c['percent'] for c in second['cores']],[50,10])
        self.assertEqual(second['cpuName'],'Intel Core i5-6500')
        self.assertIsNone(self.backend.cpu_percent((100,80),(200,100)),'counter reset is unknown')
        self.assertEqual(self.backend.cpu_percent((200,79),(100,80)),100,'negative iowait delta cannot exceed 100%')

    def test_memory_uses_available_instead_of_counting_cache_as_used(self):
        result=self.backend.memory_info((self.proc/'meminfo').read_text())
        self.assertEqual(result,{'total':1024000,'used':614400,'percent':60})
        self.assertIsNone(self.backend.memory_info('')['percent'])
        self.assertEqual(self.backend.memory_info('MemTotal: 1000 kB\nMemAvailable: 1200 kB')['used'],0)

    def test_network_elapsed_time_physical_interface_filter_and_counter_reset(self):
        def net(rx,tx):
            self.write('proc/net/dev',f'eth0: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0\nlo: 900000 0 0 0 0 0 0 0 800000 0\ntailscale0: 700000 0 0 0 0 0 0 0 600000 0')
        net(1000,500);first=self.collector.sample(now=10)
        self.assertIsNone(first['network']['download'])
        net(5096,2548);second=self.collector.sample(now=12)
        self.assertEqual(second['network'],{'download':2048,'upload':1024,'interfaces':['eth0']})
        net(0,0);self.assertEqual(self.collector.sample(now=13)['network']['download'],0)
        self.write('sys/class/net/eth0/operstate','down')
        self.assertIsNone(self.collector.sample(now=14)['network']['download'])

    def test_cpu_temperature_uses_package_and_never_nvme_or_chipset(self):
        for directory,name,label,value in [('hwmon0','nvme','Composite',99000),('hwmon1','coretemp','Package id 0',55000),('hwmon2','pch_skylake','',88000)]:
            self.write(f'sys/class/hwmon/{directory}/name',name)
            self.write(f'sys/class/hwmon/{directory}/temp1_label',label)
            self.write(f'sys/class/hwmon/{directory}/temp1_input',str(value))
        self.write('sys/class/hwmon/hwmon1/temp2_input','63000')
        self.write('sys/class/hwmon/hwmon1/temp2_label','Core 0')
        self.assertEqual(self.collector.temperature(),55)
        self.write('sys/class/hwmon/hwmon1/name','unrelated')
        self.assertIsNone(self.collector.temperature())

    def test_gpu_units_unavailable_readings_and_expanded_only_queries(self):
        gpu=self.backend.gpu_csv('NVIDIA GeForce RTX 3060, 25, 1536, 12288, 45')
        self.assertEqual(gpu['used'],1536*1024**2)
        self.assertEqual(gpu['total'],12*1024**3)
        self.assertIsNone(self.backend.gpu_csv('NVIDIA GeForce RTX 3060, N/A, N/A, 12288, N/A')['percent'])
        self.assertEqual(self.backend.gpu_csv(''),{})
        with patch.object(self.collector,'gpu',return_value=gpu) as query:
            self.collector.sample(details=False,now=1);query.assert_not_called()
            self.collector.sample(details=True,now=2);query.assert_called_once()
            self.assertEqual(self.collector.sample(details=False,now=3)['gpu'],gpu)
            query.assert_called_once()
        with patch.object(self.backend.subprocess,'run',side_effect=subprocess.TimeoutExpired('nvidia-smi',1)):
            self.assertEqual(self.collector.gpu(),{})


if __name__=='__main__':
    unittest.main()

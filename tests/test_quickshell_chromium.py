"""Browser bridge fixtures: vector/raster icons, native framing and window matching."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch
import zlib


def evaluate(expression):
    return subprocess.check_output(['nix','eval','--impure','--raw','--expr',expression],text=True)


def png():
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\0\xff\x10\x10'))+chunk(b'IEND',b'')


SVG=b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><linearGradient id="paint"><stop stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><path fill="url(#paint)" d="M1 23L12 1l11 22z"/></svg>'


class ChromiumBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        repo=Path(__file__).resolve().parents[1]
        prefix=f'let m=import {json.dumps(str(repo/"home-modules/chromium.nix"))} {{config.xdg.configHome="/fixture";pkgs={{writeTextFile = args: args.text;python3="/test-python";}};}};in '
        cls.manifest=json.loads(evaluate(prefix+'m.xdg.configFile."quickshell/chromium-extension/manifest.json".text'))
        cls.worker=evaluate(prefix+'m.xdg.configFile."quickshell/chromium-extension/${(builtins.fromJSON m.xdg.configFile."quickshell/chromium-extension/manifest.json".text).background.service_worker}".text')
        cls.native_manifest=json.loads(evaluate(prefix+'m.xdg.configFile."chromium/NativeMessagingHosts/io.quickshell.chromium_tabs.json".text'))
        cls.host=types.ModuleType('chromium_host_test')
        exec(compile(cls.native_manifest['path'],'ChromiumHost.py','exec'),cls.host.__dict__)
        source=evaluate(f'let m=import {json.dumps(str(repo/"home-modules/quickshell.nix"))} {{pkgs.writeText = name: text: text;}};in m.xdg.configFile."quickshell/WindowBackend.py".source')
        cls.backend=types.ModuleType('window_browser_test')
        exec(compile(source,'WindowBackend.py','exec'),cls.backend.__dict__)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='quickshell-chromium-test-')
        self.root=Path(self.temp.name)
        self.store=self.host.Store(self.root/'runtime',os.getpid(),self.host.identity(os.getpid())[1])

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def publish(self,title='Fixture',icon=None,window_id=1,left=0):
        self.store.update({'version':1,'windows':[{'id':window_id,'title':title,'icon':base64.b64encode(png()).decode() if icon is None else icon,'left':left,'top':0,'width':600,'height':400}]})

    def window(self,title='Fixture - Chromium',key='window',left=0):
        return {'key':key,'pid':os.getpid(),'title':title,'className':'chromium-browser','left':left,'top':0,'width':600,'height':400}

    def test_extension_identity_origin_and_minimal_permissions_match(self):
        public=base64.b64decode(self.manifest['key'])
        extension_id=''.join(chr(ord('a')+int(c,16)) for c in hashlib.sha256(public).hexdigest()[:32])
        self.assertEqual(self.native_manifest['allowed_origins'],['chrome-extension://'+extension_id+'/'])
        self.assertEqual(self.host.ORIGIN,self.native_manifest['allowed_origins'][0])
        self.assertEqual(set(self.manifest['permissions']),{'tabs','favicon','nativeMessaging','scripting'})
        self.assertEqual(self.manifest['incognito'],'not_allowed')
        self.assertEqual(set(self.manifest['host_permissions']),{'http://*/*','https://*/*'})
        self.assertNotIn('content_scripts',self.manifest)
        worker_hash=hashlib.sha256(self.worker.encode()).hexdigest()[:16]
        self.assertEqual(self.manifest['background']['service_worker'],f'background-{worker_hash}.js')

    def test_parent_browser_identity_handles_chromium_rewritten_command_line(self):
        with patch.object(self.host.os,'getppid',return_value=42), \
             patch.object(self.host,'identity',return_value=(1,123)), \
             patch.object(self.host.os,'readlink',return_value='/nix/store/browser/libexec/chromium'), \
             patch.object(self.host.Path,'read_bytes',return_value=b'/nix/store/browser/chromium --headless=new http://localhost/red\0'):
            self.assertEqual(self.host.browser_identity(),(42,123))

    def test_parent_browser_identity_handles_restricted_executable_reads(self):
        with patch.object(self.host.os,'getppid',return_value=42), \
             patch.object(self.host,'identity',return_value=(1,123)), \
             patch.object(self.host.os,'readlink',side_effect=PermissionError), \
             patch.object(self.host.Path,'read_text',return_value='chromium\n'), \
             patch.object(self.host.Path,'read_bytes',return_value=b'chromium --ozone-platform=wayland https://example.test/\0'):
            self.assertEqual(self.host.browser_identity(),(42,123))

    def test_snapshot_stores_only_private_png_and_matching_metadata(self):
        self.publish()
        state=json.loads((self.store.directory/'state.json').read_text())
        image=self.store.directory/state['windows'][0]['icon']
        self.assertEqual(image.read_bytes(),png())
        self.assertEqual(image.stat().st_mode&0o777,0o600)
        self.assertEqual((self.store.directory/'state.json').stat().st_mode&0o777,0o600)
        self.assertEqual(self.store.directory.stat().st_mode&0o777,0o700)
        self.assertNotIn('url',state['windows'][0])
        self.assertEqual(state['browserPid'],os.getpid())

    def test_svg_stays_vector_and_resolves_through_window_backend(self):
        self.publish(icon=base64.b64encode(SVG).decode())
        state=json.loads((self.store.directory/'state.json').read_text())
        image=self.store.directory/state['windows'][0]['icon']
        self.assertEqual(image.suffix,'.svg')
        self.assertIn(b'<path',image.read_bytes())
        self.assertIn(b'viewBox="0 0 24 24"',image.read_bytes())
        self.assertEqual(image.stat().st_mode&0o777,0o600)
        self.assertTrue(self.backend.BrowserIcons(self.root/'runtime').resolve([self.window()])['window'].endswith('.svg'))
        self.publish()
        self.assertFalse(image.exists(), 'old vector files must be removed when the tab changes')

    def test_svg_rejects_external_resources_entities_scripts_and_uses_raster_fallback(self):
        for content in (
            b'<!DOCTYPE svg [<!ENTITY x "expanded">]><svg>&x;</svg>',
            b'<svg><script>alert(1)</script></svg>',
            b'<svg><image href="file:///private.png"/></svg>',
            b'<svg><use href="https://example.test/art.svg#id"/></svg>',
            b'<svg onload="alert(1)"/>',
            b'<svg><style>@import "https://example.test/style";</style></svg>',
            b'<svg><path fill="url(https://example.test/paint)"/></svg>',
            b'<svg><style>path{fill:u\\72l(https://example.test/paint)}</style></svg>',
            '<!DOCTYPE svg [<!ENTITY x "expanded">]><svg>&x;</svg>'.encode('utf-16'),
        ):
            encoded=base64.b64encode(content).decode()
            self.assertIsNone(self.host.svg_bytes(encoded),content)
            self.store.update({'version':1,'windows':[{'id':1,'title':'Fixture','icon':encoded,
                'fallbackIcon':base64.b64encode(png()).decode()}]})
            state=json.loads((self.store.directory/'state.json').read_text())
            self.assertTrue(state['windows'][0]['icon'].endswith('.png'))

    def test_full_resolution_raster_is_accepted_but_dimensions_remain_bounded(self):
        data=bytearray(png());data[16:24]=struct.pack('>II',512,512)
        self.assertEqual(self.host.png_bytes(base64.b64encode(data).decode()),data)
        data[16:20]=struct.pack('>I',513)
        self.assertIsNone(self.host.png_bytes(base64.b64encode(data).decode()))

    @unittest.skipUnless(shutil.which('node'), 'requires Node for extension worker fixture')
    def test_worker_preserves_original_svg_caches_it_and_falls_back_when_fetch_fails(self):
        fixture=r'''
            const assert = require('node:assert/strict');
            const cached = Buffer.from(PNG_BASE64, 'base64');
            const original = Buffer.from(SVG_BASE64, 'base64');
            const event = {addListener(){}};
            const fetched = [];
            let links = [{url:'https://fixture.test/original.svg',type:'image/svg+xml',sizes:'any'}];
            globalThis.chrome = {
                runtime:{getURL:path=>'chrome-extension://fixture'+path, onStartup:event, onInstalled:event},
                scripting:{executeScript:async()=>[{result:{icons:links,manifest:''}}]},
                tabs:{onActivated:event,onUpdated:event},
                windows:{onCreated:event,onRemoved:event,onFocusChanged:event,onBoundsChanged:event}
            };
            globalThis.setTimeout = ()=>0;
            globalThis.fetch = async url => {
                fetched.push(String(url));
                if (String(url).includes('/_favicon/')) {
                    assert.equal(new URL(url).searchParams.get('size'),'256');
                    return new Response(cached,{headers:{'content-type':'image/png'}});
                }
                if (String(url).endsWith('/original.svg'))
                    return new Response(original,{headers:{'content-type':'image/svg+xml'}});
                return new Response('',{status:404});
            };
        '''.replace('PNG_BASE64',json.dumps(base64.b64encode(png()).decode())).replace('SVG_BASE64',json.dumps(base64.b64encode(SVG).decode()))
        scenario=r'''
            (async()=>{
                const tab={id:1,url:'https://fixture.test/',status:'complete',favIconUrl:'https://fixture.test/missing.ico'};
                const result=await favicon(tab);
                assert.deepEqual(Buffer.from(result.icon,'base64'),original);
                assert.deepEqual(Buffer.from(result.fallbackIcon,'base64'),cached);
                const count=fetched.length;
                assert.deepEqual(await favicon(tab),result);
                assert.equal(fetched.length,count,'a cached icon must not refetch on title/focus events');
                links=[{url:'https://fixture.test/missing.svg',type:'image/svg+xml',sizes:'any'}];
                const fallback=await favicon({...tab,id:2});
                assert.deepEqual(Buffer.from(fallback.icon,'base64'),cached);
                assert.deepEqual(await favicon({...tab,id:3,url:'chrome://version/'}),{icon:'',fallbackIcon:''});
            })().catch(error=>{console.error(error);process.exitCode=1});
        '''
        result=subprocess.run(['node'],input=fixture+self.worker+scenario,text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('node'), 'requires Node for extension worker fixture')
    def test_manifest_icons_resolve_relative_to_manifest_and_bad_manifests_preserve_links(self):
        fixture=r'''
            const assert = require('node:assert/strict');
            const event = {addListener(){}};
            let invalid = false;
            globalThis.chrome = {
                runtime:{onStartup:event,onInstalled:event},
                scripting:{executeScript:async()=>[{result:{
                    icons:[{url:'https://fixture.test/tiny.png',type:'image/png',sizes:'16x16'}],
                    manifest:'https://fixture.test/app/site.webmanifest'
                }}]},
                tabs:{onActivated:event,onUpdated:event},
                windows:{onCreated:event,onRemoved:event,onFocusChanged:event,onBoundsChanged:event}
            };
            globalThis.setTimeout = ()=>0;
            globalThis.fetch = async url => {
                assert.equal(String(url),'https://fixture.test/app/site.webmanifest');
                const body=invalid ? 'invalid' : JSON.stringify({icons:[
                    {src:'../large.png',type:'image/png',sizes:'512x512'},
                    {src:'file:///private.png',sizes:'1024x1024'},null
                ]});
                const response=new Response(body);
                Object.defineProperty(response,'url',{value:'https://cdn.fixture.test/app/site.webmanifest'});
                return response;
            };
        '''
        scenario=r'''
            (async()=>{
                const tab={id:1,favIconUrl:''};
                const choices=await candidates(tab);
                assert.equal(choices[0].url,'https://cdn.fixture.test/large.png');
                assert.equal(choices[1].url,'https://fixture.test/tiny.png');
                assert.equal(choices.length,2,'local-file resources are never candidates');
                invalid=true;
                const fallback=await candidates(tab);
                assert.equal(fallback.length,1);
                assert.equal(fallback[0].url,'https://fixture.test/tiny.png');
            })().catch(error=>{console.error(error);process.exitCode=1});
        '''
        result=subprocess.run(['node'],input=fixture+self.worker+scenario,text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_bad_or_absent_images_clear_site_icon_and_unknown_protocol_is_rejected(self):
        for bad in ('not base64','data:image/svg+xml,<svg/>','',base64.b64encode(b'not a png').decode()):
            self.publish(icon=bad)
            self.assertEqual(json.loads((self.store.directory/'state.json').read_text())['windows'][0]['icon'],'')
            self.assertEqual(list(self.store.directory.glob('*.png')),[])
        oversized=bytearray(png());oversized[16:20]=struct.pack('>I',100000)
        self.assertIsNone(self.host.png_bytes(base64.b64encode(oversized).decode()))
        with self.assertRaises(ValueError):self.store.update({'version':99,'windows':[]})

    def test_native_protocol_handles_short_reads_bad_json_and_oversized_frames(self):
        class Short(io.BytesIO):
            def read(self,count=-1):return super().read(min(count,3))
        good=json.dumps({'version':1,'windows':[]}).encode()
        data=struct.pack('=I',1)+b'!'+struct.pack('=I',len(good))+good
        result=io.BytesIO();self.host.serve(self.store,Short(data),result)
        frames=result.getvalue();first=struct.unpack('=I',frames[:4])[0]
        self.assertEqual(json.loads(frames[4:4+first]),{'ok':False})
        self.assertEqual(json.loads(frames[8+first:]),{'ok':True})
        result=io.BytesIO();self.host.serve(self.store,io.BytesIO(struct.pack('=I',self.host.MAX_MESSAGE+1)),result)
        self.assertEqual(result.getvalue(),b'')
        self.assertIsNone(self.host.read_exact(io.BytesIO(b'ab'),4))

    def test_reader_matches_window_pid_title_and_file_then_falls_back(self):
        self.publish()
        reader=self.backend.BrowserIcons(self.root/'runtime')
        icons=reader.resolve([self.window()])
        self.assertTrue(icons['window'].endswith('.png'))
        self.assertEqual(reader.resolve([{**self.window(),'pid':os.getpid()+1000000}]),{})
        self.assertEqual(reader.resolve([{**self.window(),'className':'kitty'}]),{})
        self.assertEqual(reader.resolve([self.window('Other - Chromium')]),{})
        self.publish(icon='')
        self.assertEqual(reader.resolve([self.window()]),{})

    def test_duplicate_titles_need_unambiguous_geometry(self):
        self.publish()
        state=json.loads((self.store.directory/'state.json').read_text())
        row=state['windows'][0]
        state['windows'].append({**row,'id':2})
        (self.store.directory/'state.json').write_text(json.dumps(state))
        reader=self.backend.BrowserIcons(self.root/'runtime')
        self.assertEqual(reader.resolve([self.window()]),{})
        state['windows'][1]['left']=900
        (self.store.directory/'state.json').write_text(json.dumps(state))
        self.assertIn('window',reader.resolve([self.window()]))

    def test_stale_host_and_path_traversal_are_never_used(self):
        self.publish()
        path=self.store.directory/'state.json';state=json.loads(path.read_text())
        state['windows'][0]['icon']='../outside.png';path.write_text(json.dumps(state))
        reader=self.backend.BrowserIcons(self.root/'runtime')
        self.assertEqual(reader.resolve([self.window()]),{})
        self.publish();state=json.loads(path.read_text());state['hostStart']+=1
        path.write_text(json.dumps(state))
        self.assertEqual(reader.resolve([self.window()]),{})
        self.store.close();self.assertFalse(self.store.directory.exists())


if __name__=='__main__':unittest.main()

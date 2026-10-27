{ config, pkgs, ... }:
let
  extensionId = "gefggahfkilgmjanbfncdedlmchgojmb";
  extensionPath = "${config.xdg.configHome}/quickshell/chromium-extension";
  # A fresh URL prevents Chromium reusing stale unpacked service-worker code.
  workerFile = "background-${builtins.substring 0 16 (builtins.hashString "sha256" workerScript)}.js";
  workerScript = ''
    /* Mirror only each normal window's active-tab icon through a local native host. */
    const HOST = "io.quickshell.chromium_tabs";
    let port = null;
    let timer = null;
    let generation = 0;
    const icons = new Map();

    function connect() {
        if (port) return port;
        const connection = chrome.runtime.connectNative(HOST);
        port = connection;
        connection.onDisconnect.addListener(() => {
            // Reading lastError consumes Chrome's diagnostic without logging tab data.
            void chrome.runtime.lastError;
            if (port === connection) {
                port = null;
                schedule(5000);
            }
        });
        return connection;
    }

    const MAX_ICON = 196608;
    const RASTER_SIZE = 512;

    function encode(bytes) {
        let binary = "";
        for (let i = 0; i < bytes.length; i += 8192)
            binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        return btoa(binary);
    }

    async function readBody(response, limit) {
        if (!response.ok || Number(response.headers.get("content-length")) > limit) return null;
        const reader = response.body.getReader();
        const chunks = []; let length = 0;
        while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            length += value.length;
            if (length > limit) { await reader.cancel(); return null; }
            chunks.push(value);
        }
        const bytes = new Uint8Array(length); let offset = 0;
        for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
        return bytes;
    }

    async function readImage(url) {
        if (!/^https?:\/\//i.test(url) && !/^data:image\//i.test(url)) return null;
        if (url.length > 180000) return null;
        try {
            const response = await fetch(url, {signal:AbortSignal.timeout(2000),
                credentials:"include", referrerPolicy:"no-referrer"});
            const bytes = await readBody(response, 1048576);
            if (!bytes) return null;
            const type = response.headers.get("content-type") || "";
            const text = new TextDecoder().decode(bytes);
            if (/image\/svg\+xml/i.test(type) || /<svg(?:\s|>)/i.test(text)) {
                // Keep vector paths intact. The host validates self-contained SVGs.
                return bytes.length <= 131072 ? {icon:encode(bytes), vector:true, size:Infinity} : null;
            }
            const bitmap = await createImageBitmap(new Blob([bytes], {type}));
            try {
                const factor = Math.min(1, RASTER_SIZE / Math.max(bitmap.width, bitmap.height));
                const canvas = new OffscreenCanvas(Math.max(1, Math.round(bitmap.width * factor)),
                    Math.max(1, Math.round(bitmap.height * factor)));
                while (true) {
                    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
                    const png = new Uint8Array(await (await canvas.convertToBlob({type:"image/png"})).arrayBuffer());
                    if (png.length <= MAX_ICON) return {icon:encode(png), vector:false,
                        size:Math.min(canvas.width, canvas.height)};
                    if (Math.max(canvas.width,canvas.height) <= 128) return null;
                    canvas.width = Math.max(1, Math.round(canvas.width * 0.75));
                    canvas.height = Math.max(1, Math.round(canvas.height * 0.75));
                }
            } finally { bitmap.close(); }
        } catch (_) { return null; }
    }

    async function candidates(tab) {
        let declared = [];
        let manifest = "";
        try {
            const result = await chrome.scripting.executeScript({target:{tabId:tab.id}, func:() => ({
                icons:Array.from(document.querySelectorAll("link[rel]")).filter(link =>
                    link.rel.toLowerCase().split(/\s+/).some(rel =>
                        rel === "icon" || rel === "apple-touch-icon" || rel === "apple-touch-icon-precomposed"))
                    .slice(0,32).map(link => ({url:link.href, type:link.type, sizes:link.getAttribute("sizes") || ""})),
                manifest:document.querySelector('link[rel~="manifest"]')?.href || ""
                })
            });
            declared = result[0]?.result?.icons || [];
            manifest = result[0]?.result?.manifest || "";
        } catch (_) { /* Protected pages still have the cache fallback. */ }
        if (/^https?:\/\//i.test(manifest)) {
            try {
                const response = await fetch(manifest, {signal:AbortSignal.timeout(2000),
                    credentials:"include", referrerPolicy:"no-referrer"});
                const bytes = await readBody(response, 65536);
                const data = bytes ? JSON.parse(new TextDecoder().decode(bytes)) : null;
                if (Array.isArray(data?.icons)) for (const icon of data.icons.slice(0,32)) {
                    if (!icon || typeof icon.src !== "string") continue;
                    try {
                        declared.push({url:new URL(icon.src, response.url || manifest).href,
                            type:typeof icon.type === "string" ? icon.type : "",
                            sizes:typeof icon.sizes === "string" ? icon.sizes : ""});
                    } catch (_) {}
                }
            } catch (_) { /* Missing/malformed manifests leave ordinary icon links intact. */ }
        }
        declared.push({url:tab.favIconUrl || "", type:"", sizes:""});
        const unique = new Map();
        for (const image of declared) {
            if (!/^https?:\/\//i.test(image.url) && !/^data:image\//i.test(image.url)) continue;
            const vector = /svg/i.test(image.type) || /\.svg(?:[?#]|$)|^data:image\/svg\+xml/i.test(image.url);
            const size = Math.max(0, ...Array.from(image.sizes.matchAll(/(\d+)x(\d+)/g), m => Math.min(+m[1], +m[2])));
            if (!unique.has(image.url)) unique.set(image.url, {...image, score:vector ? Infinity : size});
        }
        return [...unique.values()].sort((a,b) => b.score - a.score).slice(0,8);
    }

    async function favicon(tab) {
        if (!/^https?:\/\//i.test(tab.url || "")) return {icon:"", fallbackIcon:""};
        const key = tab.id + ":" + tab.url + ":" + tab.favIconUrl;
        if (icons.has(key)) return icons.get(key);
        const choices = await candidates(tab);
        const images = (await Promise.all(choices.map(image => readImage(image.url)))).filter(Boolean);
        images.sort((a,b) => b.size - a.size);
        // Keep Chromium's PNG as a fallback for unavailable/unsupported originals.
        const cache = new URL(chrome.runtime.getURL("/_favicon/"));
        cache.searchParams.set("pageUrl", tab.url);
        cache.searchParams.set("size", "256");
        let cached = "";
        try {
            const response = await fetch(cache, {signal:AbortSignal.timeout(2000)});
            if (response.ok) {
                const bytes = new Uint8Array(await response.arrayBuffer());
                if (bytes.length <= MAX_ICON) cached = encode(bytes);
            }
        } catch (_) {}
        const best = images[0];
        const result = {icon:best?.icon || cached,
            fallbackIcon:best?.vector ? (images.find(image => !image.vector)?.icon || cached) : ""};
        if (result.icon && tab.status !== "loading") {
            icons.set(key, result);
            if (icons.size > 128) icons.delete(icons.keys().next().value);
        }
        return result;
    }

    async function publish(serial) {
        try {
            const windows = await chrome.windows.getAll({populate:true, windowTypes:["normal", "popup"]});
            const entries = await Promise.all(windows.filter(w => !w.incognito).slice(0,32).map(async window => {
                const tab = window.tabs?.find(t => t.active);
                if (!tab) return null;
                return {id:window.id, title:tab.title || "", left:window.left, top:window.top,
                    width:window.width, height:window.height, ...await favicon(tab)};
            }));
            if (serial !== generation) return;
            const message = {version:1, windows:entries.filter(Boolean)};
            // Native messaging frames are capped at 1 MiB, including every window.
            for (const entry of message.windows) {
                entry.title = entry.title.slice(0,2048);
            }
            const metadata = {version:1, windows:message.windows.map(entry =>
                ({...entry, icon:"", fallbackIcon:""}))};
            let budget = 1048576 - new TextEncoder().encode(JSON.stringify(metadata)).length - 4096;
            for (const entry of message.windows) {
                for (const field of ["icon", "fallbackIcon"]) {
                    if (entry[field].length > budget) entry[field] = "";
                    budget -= entry[field].length;
                }
            }
            connect().postMessage(message);
        } catch (_) {
            // A disappearing tab or host is retried on the next browser event.
        }
    }

    function schedule(delay = 80) {
        const serial = ++generation;
        clearTimeout(timer);
        timer = setTimeout(() => publish(serial), delay);
    }

    chrome.tabs.onActivated.addListener(() => schedule());
    chrome.tabs.onUpdated.addListener((_id, changes, tab) => {
        if (["favIconUrl", "url", "status"].some(key => key in changes))
            for (const key of icons.keys()) if (key.startsWith(tab.id + ":")) icons.delete(key);
        if (tab.active && ["favIconUrl", "title", "url", "status"].some(key => key in changes)) schedule();
    });
    chrome.windows.onCreated.addListener(() => schedule());
    chrome.windows.onRemoved.addListener(() => schedule());
    chrome.windows.onFocusChanged.addListener(() => schedule());
    chrome.windows.onBoundsChanged.addListener(() => schedule());
    chrome.runtime.onStartup.addListener(() => schedule());
    chrome.runtime.onInstalled.addListener(() => schedule());
    schedule(0);
  '';
  nativeHost = pkgs.writeTextFile {
    name = "quickshell-chromium-host";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      """Local native-messaging host. No network, browser control or persistent history."""
      import base64
      import hashlib
      import json
      import os
      from pathlib import Path
      import re
      import shutil
      import signal
      import struct
      import sys
      import tempfile
      import xml.etree.ElementTree as ET

      ORIGIN = 'chrome-extension://gefggahfkilgmjanbfncdedlmchgojmb/'
      MAX_MESSAGE = 1024*1024


      def identity(pid):
          try:
              fields = Path('/proc',str(pid),'stat').read_text().rsplit(')',1)[1].split()
              return int(fields[1]), int(fields[19])
          except (OSError, ValueError, IndexError):
              return None


      def browser_identity():
          pid = os.getppid()
          while pid > 1:
              item = identity(pid)
              if not item:
                  break
              try:
                  # Chromium may rewrite cmdline to one space-separated argument.
                  try:
                      name = Path(os.readlink('/proc/'+str(pid)+'/exe')).name.lower()
                  except OSError:
                      # The live browser can restrict exe reads, including from its host.
                      name = Path('/proc',str(pid),'comm').read_text().strip().lower()
                  command = Path('/proc',str(pid),'cmdline').read_bytes().replace(b'\0',b' ')
                  if ('chromium' in name or 'chrome' in name) and not re.search(br'(?:^|\s)--type=',command):
                      return pid,item[1]
              except OSError:
                  pass
              pid = item[0]
          raise ValueError('Native host must be started by Chromium')


      def png_bytes(encoded):
          if not isinstance(encoded,str) or len(encoded)>262144:
              return None
          try:
              data = base64.b64decode(encoded,validate=True)
              if len(data)<33 or data[:8]!=b'\x89PNG\r\n\x1a\n' or data[12:16]!=b'IHDR':
                  return None
              width,height = struct.unpack('>II',data[16:24])
              return data if 0<width<=512 and 0<height<=512 else None
          except (ValueError,struct.error):
              return None


      def svg_bytes(encoded):
          """Keep scalable, self-contained artwork; never resolve files or URLs."""
          if not isinstance(encoded,str) or len(encoded)>174764:
              return None
          try:
              data = base64.b64decode(encoded,validate=True)
              # ElementTree does not fetch resources; exclude entity expansion too.
              if b'\0' in data or b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
                  return None
              root = ET.fromstring(data)
              namespace = 'http://www.w3.org/2000/svg'
              if root.tag not in ('svg','{'+namespace+'}svg'):
                  return None
              allowed = set('svg g defs path rect circle ellipse line polyline polygon '
                            'linearGradient radialGradient stop clipPath mask symbol use '
                            'title desc text tspan style pattern marker'.split())
              nodes = list(root.iter())
              if len(nodes)>4096:
                  return None
              def safe_value(value):
                  if '\\' in value or '@' in value:
                      return False
                  return all(re.fullmatch(r"\s*[\"']?#[\w:.-]+[\"']?\s*",url)
                             for url in re.findall(r'url\s*\((.*?)\)',value,re.I|re.S))
              for node in nodes:
                  tag = node.tag.rsplit('}',1)[-1]
                  if tag not in allowed or (node.tag.startswith('{') and not node.tag.startswith('{'+namespace+'}')):
                      return None
                  if tag=='style' and not safe_value(node.text or '''):
                      return None
                  for key,value in node.attrib.items():
                      name = key.rsplit('}',1)[-1].lower()
                      if name.startswith('on') or name=='base' or not safe_value(value):
                          return None
                      if name=='href' and not re.fullmatch(r'#[\w:.-]+',value):
                          return None
              ET.register_namespace(''',namespace)
              return ET.tostring(root,encoding='utf-8')
          except (ValueError,ET.ParseError,RecursionError):
              return None


      class Store:
          def __init__(self, root, browser_pid, browser_start):
              root.mkdir(mode=0o700,parents=True,exist_ok=True)
              self.directory = Path(tempfile.mkdtemp(prefix='host-',dir=root))
              self.directory.chmod(0o700)
              self.pid,self.start = os.getpid(),identity(os.getpid())[1]
              self.browser_pid,self.browser_start = browser_pid,browser_start

          def update(self, message):
              if not isinstance(message,dict) or message.get('version')!=1 or not isinstance(message.get('windows'),list):
                  raise ValueError('Invalid browser snapshot')
              windows,keep = [],set()
              for window in message['windows'][:32]:
                  if not isinstance(window,dict) or not isinstance(window.get('id'),int) or not isinstance(window.get('title'),str):
                      continue
                  row = {'id':window['id'],'title':window['title'][:2048],'icon':'''}
                  for key in ('left','top','width','height'):
                      value = window.get(key)
                      row[key] = value if isinstance(value,int) and abs(value)<100000 else 0
                  image = svg_bytes(window.get('icon'))
                  suffix = '.svg' if image else '.png'
                  image = image or png_bytes(window.get('icon')) or png_bytes(window.get('fallbackIcon'))
                  if image:
                      name=hashlib.sha256(image).hexdigest()+suffix
                      path=self.directory/name
                      if not path.exists():
                          path.write_bytes(image)
                          path.chmod(0o600)
                      keep.add(name)
                      row['icon']=name
                  windows.append(row)
              state={'version':1,'hostPid':self.pid,'hostStart':self.start,
                     'browserPid':self.browser_pid,'browserStart':self.browser_start,'windows':windows}
              temp=self.directory/'state.tmp'
              temp.write_text(json.dumps(state,ensure_ascii=False))
              temp.chmod(0o600)
              temp.replace(self.directory/'state.json')
              for path in list(self.directory.glob('*.png'))+list(self.directory.glob('*.svg')):
                  if path.name not in keep:
                      path.unlink(missing_ok=True)

          def close(self):
              shutil.rmtree(self.directory,ignore_errors=True)


      def read_exact(stream, count):
          result=bytearray()
          while len(result)<count:
              data=stream.read(count-len(result))
              if not data:
                  return None
              result.extend(data)
          return bytes(result)


      def serve(store, incoming, outgoing):
          while True:
              header=read_exact(incoming,4)
              if header is None:
                  break
              length=struct.unpack('=I',header)[0]
              if length>MAX_MESSAGE:
                  break
              payload=read_exact(incoming,length)
              if payload is None:
                  break
              try:
                  store.update(json.loads(payload))
                  response=b'{"ok":true}'
              except (ValueError,TypeError):
                  response=b'{"ok":false}'
              outgoing.write(struct.pack('=I',len(response))+response)
              outgoing.flush()


      def main():
          if len(sys.argv)<2 or sys.argv[1]!=ORIGIN:
              return
          runtime=os.environ.get('XDG_RUNTIME_DIR')
          if not runtime:
              return
          store=None
          def halt(*_):
              raise SystemExit(0)
          signal.signal(signal.SIGTERM,halt)
          signal.signal(signal.SIGINT,halt)
          try:
              pid,start=browser_identity()
              store=Store(Path(runtime)/'quickshell-chromium',pid,start)
              serve(store,sys.stdin.buffer,sys.stdout.buffer)
          except (OSError,ValueError,BrokenPipeError):
              pass
          finally:
              if store:
                  store.close()


      if __name__=='__main__':
          main()
    '';
  };
in
{
  xdg.configFile."quickshell/chromium-extension/manifest.json".text = ''
    {
      "manifest_version": 3,
      "name": "Quickshell tab icons",
      "version": "1.1.1",
      "description": "Send active-tab favicons to the local Quickshell window panel.",
      "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3jaT4nqkJtUfv/XbeZawDZX1bk4s3Ugl2vr+En+17Egn3Yjt79beXYX3J4C50mRUi47vUn+R2PGXARno9z0+LgSMq3//cWe2rW1VZftzuLUEde+TBeVgqvoQlxIzOhfDx+5PbrXB/MMwnSYR3WFIM3UXl7zeESZ1KxabxnaQoh1qR/F3OjTeovhrNKJOLTAxK7WXMTVl1+qOm389gBu+gd5+riXFyP4FqF3CMA7xSDRhiV1FpE172LDLnw+xdQ8zO36QuI9LYujCSRgRVVsQmGPNskAP5fnY/NI5DdfcpkueTrehrzfT/SeutQxoDLVo8OyplacdaPN7lt2vbyNl0QIDAQAB",
      "permissions": [
        "tabs",
        "favicon",
        "nativeMessaging",
        "scripting"
      ],
      "host_permissions": ["http://*/*", "https://*/*"],
      "background": {
        "service_worker": "${workerFile}"
      },
      "incognito": "not_allowed",
      "minimum_chrome_version": "109"
    }
  '';

  xdg.configFile."quickshell/chromium-extension/${workerFile}".text = workerScript;

  xdg.configFile."chromium/NativeMessagingHosts/io.quickshell.chromium_tabs.json".text = builtins.toJSON {
    name = "io.quickshell.chromium_tabs";
    description = "Quickshell active-tab icons";
    path = "${nativeHost}";
    type = "stdio";
    allowed_origins = [ "chrome-extension://${extensionId}/" ];
  };

  programs.chromium = {
    enable = true;

    commandLineArgs = [
      "--load-extension=${extensionPath}"
      "--ozone-platform=wayland"
      "--enable-features=WaylandWindowDecorations"
    ];

    dictionaries = [
      pkgs.hunspellDictsChromium.en_US
    ];

    extensions = [
      # uBlock Origin Lite
      { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; }
      # Dark Reader
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }
      # gruvbox slate not anymore hehehehje
      { id = "oabmjgpgajjcdhogjkffbimhfjjobpii"; }
    ];
  };
}

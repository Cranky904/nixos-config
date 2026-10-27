"""Playlist storage/download semantics and real silent mpv IPC, without user files."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import types
import unittest
from unittest.mock import patch
import wave


class PlaylistBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module = Path(__file__).resolve().parents[1] / 'home-modules/quickshell.nix'
        expression = f'let m=import {json.dumps(str(module))} {{pkgs.writeText = name: text: text;}};in m.xdg.configFile."quickshell/PlaylistBackend.py".source'
        source = subprocess.check_output(['nix', 'eval', '--impure', '--raw', '--expr', expression], text=True)
        cls.backend = types.ModuleType('playlist_backend_test')
        exec(compile(source, 'PlaylistBackend.py', 'exec'), cls.backend.__dict__)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='playlist-backend-test-')
        self.root = Path(self.directory.name) / 'Playlists'
        self.events = []
        self.library = self.backend.Library(self.root, self.events.append)

    def tearDown(self):
        self.library.close()
        self.directory.cleanup()

    def add_playlist(self, name='Local'):
        folder = self.root / name
        folder.mkdir()
        for name in ['a.wav', 'b.wav']:
            with wave.open(str(folder / name), 'wb') as output:
                output.setnchannels(1); output.setsampwidth(2); output.setframerate(8000)
                output.writeframes(b'\0\0' * 8000 * 10)
        self.library.scan()
        self.library.select(folder.name)
        return folder

    def test_youtube_playlist_validation_and_library_path_boundaries(self):
        _, url = self.backend.playlist_url('https://www.youtube.com/watch?v=abcdefghijk&list=PLfixture_123')
        self.assertEqual(url, 'https://www.youtube.com/playlist?list=PLfixture_123')
        for value in ['https://example.org/?list=PLfixture_123', 'file:///etc/passwd?list=PLfixture_123', 'https://youtube.com/watch?v=abcdefghijk']:
            with self.assertRaises(ValueError): self.backend.playlist_url(value)
        outside = Path(self.directory.name) / 'outside'; outside.mkdir()
        (outside / 'keep').write_text('untouched')
        (self.root / 'escape').symlink_to(outside, target_is_directory=True)
        for key in ['../outside', '.', 'escape']:
            with self.assertRaises(ValueError): self.library.folder(key)
        self.library.scan()
        self.assertNotIn('escape', self.library.playlists)
        self.assertTrue((outside / 'keep').exists())

    def test_exclusions_persist_and_trash_deletion_is_recoverable(self):
        folder = self.add_playlist()
        self.library.skip('a.wav')
        self.library.scan()
        self.assertTrue(self.library.snapshot()['tracks'][0]['skipped'])
        self.library.skip('a.wav')
        self.assertFalse(self.library.snapshot()['tracks'][0]['skipped'])
        with patch.dict(os.environ, {'XDG_DATA_HOME': str(Path(self.directory.name) / 'data')}):
            self.library.delete()
        self.assertFalse(folder.exists())
        trash = Path(self.directory.name) / 'data/Trash'
        moved = list((trash / 'files').iterdir())
        self.assertEqual(len(moved), 1)
        self.assertTrue((moved[0] / 'a.wav').is_file())
        self.assertIn('Path=', next((trash / 'info').iterdir()).read_text())
        self.assertEqual(self.library.snapshot()['selected'], '')

    def test_download_progress_resume_update_and_exclusion_preservation(self):
        ids = ['aaaaaaaaaaa', 'bbbbbbbbbbb']
        calls = []
        library = self.library
        class FakeProcess:
            returncode = 0
            def __init__(self, args, **kwargs):
                self.args = args
                self.stdout = io.StringIO('')
                if '--flat-playlist' not in args:
                    template = Path(args[args.index('-o') + 1]); filename = Path(str(template).replace('%(ext)s', 'opus'))
                    filename.write_bytes(b'fixture-audio')
                    filename.with_suffix('.jpg').write_bytes(b'fixture-art')
                    filename.with_suffix('.info.json').write_text(json.dumps({'artist': 'Fixture artist'}))
                    self.stdout = io.StringIO('QS_PROGRESS:25.0%\nQS_PROGRESS:100.0%\nQS_FILE:' + json.dumps(str(filename)) + '\n')
                    calls.append(filename.name)
            def communicate(self, timeout=None):
                return json.dumps({'title': 'Fixture playlist', 'entries': [{'id': key, 'title': key, 'uploader': 'Artist'} for key in ids]}), None
            def wait(self, timeout=None): return self.returncode
            def poll(self): return self.returncode
        url = 'https://www.youtube.com/playlist?list=PLfixture_123'
        with patch.object(self.backend.subprocess, 'Popen', FakeProcess):
            library.busy = True; library.download(url)
            self.assertEqual(calls, ['aaaaaaaaaaa.opus', 'bbbbbbbbbbb.opus'])
            self.assertTrue(any(any(track.get('progress') == .25 for track in event['tracks']) for event in self.events))
            self.assertTrue(all(track['state'] == 'ready' for track in library.snapshot()['tracks']))
            library.skip(ids[0])
            ids[:] = ['bbbbbbbbbbb', 'aaaaaaaaaaa', 'ccccccccccc']
            library.busy = True; library.download(url)
        self.assertEqual(calls, ['aaaaaaaaaaa.opus', 'bbbbbbbbbbb.opus', 'ccccccccccc.opus'])
        tracks = library.snapshot()['tracks']
        self.assertEqual([track['id'] for track in tracks], ids)
        self.assertTrue(tracks[1]['skipped'])
        self.assertEqual(tracks[0]['artist'], 'Fixture artist')
        self.assertFalse(library.busy)
        self.assertEqual(library.error, '')

    def test_failed_metadata_keeps_the_existing_playlist(self):
        self.add_playlist()
        class FailedProcess:
            returncode = 1
            def communicate(self, timeout=None): return 'network unavailable', None
            def poll(self): return 1
        with patch.object(self.backend.subprocess, 'Popen', lambda *a, **k: FailedProcess()):
            self.library.busy = True
            self.library.download('https://www.youtube.com/playlist?list=PLfixture_123')
        self.assertEqual(len(self.library.snapshot()['tracks']), 2)
        self.assertIn('Could not read', self.library.error)
        self.assertFalse(self.library.busy)

    @unittest.skipUnless(shutil.which('mpv'), 'requires mpv')
    def test_real_mpv_play_pause_next_and_excluded_track_with_silent_output(self):
        self.add_playlist()
        self.library.player = self.backend.Player(self.library.player_changed, lambda: self.library.next_track(1), shutil.which('mpv'), ['--ao=null'])
        def wait_for(predicate):
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                if predicate(): return
                time.sleep(.03)
            self.fail(str(self.library.snapshot()))
        self.library.play('a.wav')
        wait_for(lambda: self.library.current['playing'])
        self.library.command({'action': 'toggle'})
        wait_for(lambda: not self.library.current['playing'])
        wait_for(lambda: self.library.current.get('duration', 0) == 10)
        self.library.command({'action': 'seek', 'position': 7})
        wait_for(lambda: abs(self.library.current.get('position', 0) - 7) < .1)
        self.assertFalse(self.library.current['playing'], 'seeking preserves pause')
        self.library.command({'action': 'seek', 'position': -3})
        wait_for(lambda: self.library.current.get('position', -1) == 0)
        for invalid in [float('nan'), float('inf'), '7', True]:
            with self.assertRaises(ValueError):
                self.library.command({'action': 'seek', 'position': invalid})
        self.library.command({'action': 'next'})
        wait_for(lambda: self.library.current.get('track') == 'b.wav' and not self.library.current['playing'])
        self.library.command({'action': 'toggle'})
        wait_for(lambda: self.library.current['playing'])
        self.library.skip('b.wav')
        wait_for(lambda: self.library.current.get('track') == 'a.wav')
        self.library.skip('b.wav')
        self.library.command({'action': 'toggle'})
        wait_for(lambda: not self.library.current['playing'])
        self.library.skip('a.wav')
        wait_for(lambda: self.library.current.get('track') == 'b.wav' and not self.library.current['playing'])
        process = self.library.player.process
        self.library.close()
        self.assertIsNotNone(process.poll())


if __name__ == '__main__':
    unittest.main()

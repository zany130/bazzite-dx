"""No ESP access: exercise user seeding and Atomic binary migration in fake roots."""
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / 'system_files/usr/libexec/bazzite-dx-refind-seed'
loader = importlib.machinery.SourceFileLoader('sync', str(ROOT / 'system_files/usr/libexec/bazzite-dx-refind-sync'))
spec = importlib.util.spec_from_loader(loader.name, loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)


class Seeding(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.source = self.base / 'source'
        for directory in ('GUI', 'icons', 'backgrounds', 'themes'):
            (self.source / directory).mkdir(parents=True)
            (self.source / directory / 'asset').write_text('bundled')
        for name in ('refind_install_package_mgr.sh', 'refind_install_Sourceforge.sh',
                     'uninstall_rEFInd.sh', 'scan_esp.sh', 'refind-GUI.conf'):
            (self.source / name).write_text('bundled')
            (self.source / name).chmod(0o755 if name.endswith('.sh') else 0o644)
        for i in range(7):
            (self.source / 'themes' / str(i)).mkdir()
        self.target = self.home / '.local/rEFInd_GUI'

    def run_seed(self, success=True):
        result = subprocess.run(['python3', str(SEED), str(self.source)],
                                env={**os.environ, 'HOME': str(self.home)}, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stderr.decode())

    def test_fresh_repeat_upgrade(self):
        (self.source / 'refind_install_package_mgr.sh').chmod(0o644)
        self.run_seed()
        self.assertEqual((self.target / 'refind_install_package_mgr.sh').stat().st_mode & 0o777, 0o755)
        self.assertEqual(len(list((self.target / 'themes').iterdir())), 8)
        self.assertEqual(os.readlink(self.target / 'GUI/themes'), '../themes')
        custom = self.target / 'GUI/refind.conf'
        custom.write_text('custom settings')
        (self.target / 'themes/asset').write_text('custom theme')
        (self.target / 'scan_esp.sh').write_text('custom script')
        (self.source / 'themes/new-theme').write_text('new release')
        self.run_seed()
        self.run_seed()
        self.assertEqual(custom.read_text(), 'custom settings')
        self.assertEqual((self.target / 'themes/asset').read_text(), 'custom theme')
        self.assertEqual((self.target / 'scan_esp.sh').read_text(), 'custom script')
        self.assertEqual((self.target / 'themes/new-theme').read_text(), 'new release')

    def test_existing_and_dangling_shortcuts(self):
        self.run_seed()
        (self.target / 'GUI/themes').unlink()
        (self.target / 'GUI/themes').symlink_to('custom-missing')
        (self.target / 'GUI/backgrounds').unlink()
        (self.target / 'GUI/backgrounds').mkdir()
        self.run_seed()
        self.assertEqual(os.readlink(self.target / 'GUI/themes'), 'custom-missing')
        self.assertTrue((self.target / 'GUI/backgrounds').is_dir())

    def test_symlink_gui_refused(self):
        self.run_seed()
        import shutil
        shutil.rmtree(self.target / 'GUI')
        outside = self.base / 'outside'
        outside.mkdir()
        (self.target / 'GUI').symlink_to(outside)
        self.run_seed(False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlink_parent_refused(self):
        outside = self.base / 'outside'
        outside.mkdir()
        (self.home / '.local').symlink_to(outside)
        self.run_seed(False)
        self.assertEqual(list(outside.iterdir()), [])


class Migration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ('usr/share/rEFInd_GUI', 'usr/libexec/rEFInd_GUI', 'etc/rEFInd', 'var/lib'):
            (self.root / directory).mkdir(parents=True)
        # The fake root is owned by the test user. Retain real type/mode checks.
        def trusted(path, directory=False):
            info = path.lstat()
            return (info.st_uid == os.getuid() and info.st_gid == os.getgid()
                        and not info.st_mode & 0o022
                        and (path.is_dir() and not path.is_symlink() if directory
                             else path.is_file() and not path.is_symlink()))
        self.addCleanup(patch.stopall)
        patch.object(sync, 'trusted', side_effect=trusted).start()
        self.old = b'packaged old'
        self.new = b'packaged new'
        self.known = {}
        for name in ('rEFInd_GUI', 'rEFInd_GUI_helper'):
            (self.root / 'usr/libexec/rEFInd_GUI' / name).write_bytes(self.new)
            (self.root / 'etc/rEFInd' / name).write_bytes(self.old)
            self.known[name] = [hashlib.sha256(data).hexdigest() for data in (self.old, self.new)]
        self.manifest = self.root / 'usr/share/rEFInd_GUI/packaged-binaries.json'
        self.manifest.write_text(json.dumps(self.known))
        self.helper = self.root / 'etc/rEFInd/rEFInd_GUI_helper'

    def test_known_upgrade_repeat_and_future_upgrade(self):
        sync.sync(self.root)
        sync.sync(self.root)
        self.assertEqual(self.helper.read_bytes(), self.new)
        self.assertEqual(self.helper.stat().st_mode & 0o777, 0o755)
        future = b'future release'
        for name in self.known:
            (self.root / 'usr/libexec/rEFInd_GUI' / name).write_bytes(future)
            self.known[name] = [hashlib.sha256(future).hexdigest()]
        self.manifest.write_text(json.dumps(self.known))
        sync.sync(self.root)
        self.assertEqual(self.helper.read_bytes(), future)

    def test_customized_preserved(self):
        self.helper.write_bytes(b'custom privileged binary')
        sync.sync(self.root)
        self.assertEqual(self.helper.read_bytes(), b'custom privileged binary')

    def test_destination_link_preserved(self):
        self.helper.unlink()
        outside = self.root / 'outside'
        outside.write_bytes(self.old)
        self.helper.symlink_to(outside)
        sync.sync(self.root)
        self.assertTrue(self.helper.is_symlink())
        self.assertEqual(outside.read_bytes(), self.old)

    def test_unsafe_permissions_preserved(self):
        self.helper.chmod(0o777)
        sync.sync(self.root)
        self.assertEqual(self.helper.read_bytes(), self.old)

    def test_unsafe_state_refused(self):
        sync.sync(self.root)
        (self.root / 'var/lib/bazzite-dx/refind-binaries.json').chmod(0o666)
        with self.assertRaises(RuntimeError):
            sync.sync(self.root)

    def test_parent_link_refused(self):
        import shutil
        shutil.rmtree(self.root / 'etc/rEFInd')
        (self.root / 'etc/rEFInd').symlink_to(self.root / 'usr/libexec/rEFInd_GUI')
        with self.assertRaises(RuntimeError):
            sync.sync(self.root)

    def test_untrusted_source_fails(self):
        (self.root / 'usr/libexec/rEFInd_GUI/rEFInd_GUI_helper').write_bytes(b'wrong payload')
        with self.assertRaises(RuntimeError):
            sync.sync(self.root)
        self.assertEqual(self.helper.read_bytes(), self.old)

class EditorSetup(unittest.TestCase):
    def test_failed_install_retries_and_preserves_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            settings = home / '.config/Code/User/settings.json'
            settings.parent.mkdir(parents=True)
            settings.write_text('custom settings')
            tools = home / 'bin'
            tools.mkdir()
            code = tools / 'code'
            code.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$HOME/calls"\n[[ ! -e "$HOME/fail" ]]\n')
            code.chmod(0o755)
            hook = ROOT / 'system_files/usr/share/ublue-os/user-setup.hooks.d/11-vscode-extensions.sh'
            env = {**os.environ, 'HOME': tmp, 'PATH': str(tools) + ':' + os.environ['PATH'],
                   'XDG_STATE_HOME': str(home / '.local/state')}
            marker = home / '.local/state/bazzite-dx/vscode-extensions-v1'
            (home / 'fail').touch()
            self.assertNotEqual(subprocess.run(['bash', str(hook)], env=env).returncode, 0)
            self.assertFalse(marker.exists())
            (home / 'fail').unlink()
            self.assertEqual(subprocess.run(['bash', str(hook)], env=env).returncode, 0)
            self.assertTrue(marker.exists())
            self.assertEqual(subprocess.run(['bash', str(hook)], env=env).returncode, 0)
            self.assertEqual(len((home / 'calls').read_text().splitlines()), 4)
            self.assertEqual(settings.read_text(), 'custom settings')


if __name__ == '__main__':
    unittest.main()

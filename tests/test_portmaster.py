"""Filesystem lifecycle tests; systemd/network/SELinux are mocked, never host-modified."""
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'system_files/usr/libexec/bazzite-dx-portmaster'
SOURCE = ROOT / 'system_files/usr/share/bazzite-dx/portmaster'
loader = importlib.machinery.SourceFileLoader('portmaster_installer', str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
pm = importlib.util.module_from_spec(spec)
loader.exec_module(pm)


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'root'
        self.root.mkdir()
        self.source = self.root / 'usr/share/bazzite-dx/portmaster'
        shutil.copytree(SOURCE, self.source)
        artifacts = []
        for name in ('portmaster', 'portmaster-core', 'assets.zip', 'portmaster.zip'):
            artifacts.append({'Filename': name, 'URLs': ['https://example.invalid/' + name],
                              'SHA256': hashlib.sha256(('payload-' + name).encode()).hexdigest()})
        (self.source / 'bootstrap.json').write_text(json.dumps({'Version': 'test', 'Artifacts': artifacts}))
        self.calls = []
        self.labels = set()
        self.active = {'firewalld.service'}
        self.enabled = {'firewalld.service'}
        self.fail = None
        self.addCleanup(patch.stopall)
        patch.object(pm, 'run', side_effect=self.command).start()
        patch.object(pm.shutil, 'which', return_value='/usr/bin/tool').start()
        patch.object(pm.platform, 'machine', return_value='x86_64').start()
        self.inst = pm.Installer(self.root, self.source)

    def command(self, *args, check=True):
        self.calls.append(args)
        rc, output = 0, ''
        if self.fail and self.fail(args):
            rc = 1
        elif args[0] == 'curl':
            target = Path(args[args.index('--output') + 1])
            target.write_text('payload-' + target.name)
        elif args[0] == 'systemctl':
            action, name = args[1], args[-1]
            if action == 'is-active':
                rc = 0 if name in self.active else 3
            elif action == 'is-enabled':
                output = 'enabled' if name in self.enabled else 'disabled'
                rc = 0 if name in self.enabled else 1
            elif action == 'stop':
                self.active.discard(name)
            elif action == 'start':
                self.active.add(name)
            elif action == 'enable':
                self.enabled.add(name)
                if '--now' in args:
                    self.active.add(name)
            elif action == 'disable':
                self.enabled.discard(name)
                if '--now' in args:
                    self.active.discard(name)
        elif args[0] == 'semanage':
            if '-l' in args:
                output = '\n'.join(f'{rule} all files system_u:object_r:bin_t:s0' for rule in self.labels)
            elif '-a' in args:
                self.labels.add(args[-1])
            elif '-d' in args:
                self.labels.remove(args[-1])
        if rc and check:
            raise subprocess.CalledProcessError(rc, args, output, 'injected failure')
        return subprocess.CompletedProcess(args, rc, output, '')

    def file(self, name, content='old'):
        path = self.inst.path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_install_repeat_does_not_enable_or_redownload(self):
        self.inst.install()
        config = self.file(pm.DATA + '/config.json', 'user config')
        self.calls.clear()
        self.inst.install()
        self.assertFalse(any(call[0] == 'curl' for call in self.calls))
        self.assertNotIn('portmaster.service', self.enabled)
        self.assertIn('firewalld.service', self.active)
        self.assertEqual(config.read_text(), 'user config')
        self.assertEqual(self.inst.path(pm.DATA + '/bin').stat().st_mode & 0o777, 0o755)
        self.assertFalse(self.inst.path(pm.AUTOSTART).exists())

    def test_self_update_keeps_integration_and_repair_keeps_new_version(self):
        self.inst.install()
        before = {name: self.inst.path(name).read_bytes() for name in (pm.UNIT, pm.PROFILE)}
        binary = self.inst.path(pm.DATA + '/bin')
        # Model upstream's replacement of *every* file in the configured bin directory.
        for path in binary.iterdir():
            path.unlink()
        for name in ('portmaster', 'portmaster-core', 'assets.zip', 'portmaster.zip', 'index.json'):
            (binary / name).write_text('new version')
        self.inst.install()
        self.assertEqual((binary / 'portmaster-core').read_text(), 'new version')
        for name, contents in before.items():
            self.assertEqual(self.inst.path(name).read_bytes(), contents)
        self.assertEqual({p.name for p in binary.iterdir()},
                         {'portmaster', 'portmaster-core', 'assets.zip', 'portmaster.zip', 'index.json'})

    def test_enable_disable_restores_firewalld(self):
        self.inst.install()
        self.inst.enable()
        self.inst.enable()
        self.assertIn('portmaster.service', self.enabled)
        self.assertNotIn('firewalld.service', self.enabled)
        self.assertIn('--background', self.inst.path(pm.AUTOSTART).read_text())
        self.inst.disable()
        self.inst.disable()
        self.assertIn('firewalld.service', self.enabled)
        self.assertIn('firewalld.service', self.active)
        self.assertNotIn('portmaster.service', self.active)

    def test_enable_failure_restores_firewall(self):
        self.inst.install()
        self.fail = lambda a: a == ('systemctl', 'enable', '--now', 'portmaster.service')
        with self.assertRaises(subprocess.CalledProcessError):
            self.inst.enable()
        self.assertIn('firewalld.service', self.active)
        self.assertIn('firewalld.service', self.enabled)

    def test_initial_download_failure_leaves_running_service_untouched(self):
        self.active.add('portmaster.service')
        self.fail = lambda a: a[0] == 'curl'
        with self.assertRaises(subprocess.CalledProcessError):
            self.inst.install()
        self.assertIn('portmaster.service', self.active)
        self.assertFalse(self.inst.path(pm.UNIT).exists())

    def test_checksum_failure_before_service_changes(self):
        data = json.loads((self.source / 'bootstrap.json').read_text())
        data['Artifacts'][0]['SHA256'] = '0' * 64
        (self.source / 'bootstrap.json').write_text(json.dumps(data))
        with self.assertRaisesRegex(RuntimeError, 'checksum'):
            self.inst.install()
        self.assertFalse(any(a[:2] == ('systemctl', 'stop') for a in self.calls))

    def test_reboot_and_rebase_keep_activation_and_persistent_management(self):
        self.inst.install()
        self.inst.enable()
        self.active.clear()  # Reboot: systemd's enabled state persists.
        self.active.update(self.enabled)
        persistent = self.inst.base / 'resources'
        shutil.rmtree(self.source)  # Rebase removes image-provided templates.
        again = pm.Installer(self.root, persistent)
        again.install()
        self.assertIn('portmaster.service', self.active)
        self.assertTrue((again.base / 'manage').is_file())
        again.uninstall()
        self.assertIn('firewalld.service', self.active)

    def test_uninstall_preserves_data_and_reinstallation(self):
        self.inst.install()
        config = self.file(pm.DATA + '/config.json', 'preserve')
        self.inst.enable()
        self.inst.uninstall()
        self.assertEqual(config.read_text(), 'preserve')
        self.assertFalse(self.inst.path(pm.UNIT).exists())
        self.assertFalse(self.inst.path(pm.PROFILE).exists())
        self.assertEqual(self.labels, set())
        again = pm.Installer(self.root, self.source)
        again.uninstall()
        again.install()
        self.assertEqual(config.read_text(), 'preserve')

    def test_customized_service_refused_without_stopping(self):
        self.inst.install()
        self.inst.path(pm.UNIT).write_text('custom service')
        self.calls.clear()
        with self.assertRaisesRegex(RuntimeError, 'customized'):
            self.inst.install()
        with self.assertRaisesRegex(RuntimeError, 'customized'):
            self.inst.uninstall()
        self.assertFalse(self.calls)

    def test_symlink_and_writable_binary_refused(self):
        binary = self.inst.path(pm.DATA + '/bin')
        binary.parent.mkdir(parents=True)
        binary.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
            self.inst.install()
        binary.unlink()
        self.inst.install()
        (binary / 'portmaster-core').chmod(0o777)
        with self.assertRaisesRegex(RuntimeError, 'Untrusted'):
            self.inst.install()

    def test_gist_exports_moved_not_deleted(self):
        self.inst.install()
        export = self.file(pm.DATA + '/bin/exports/share/custom', 'preserve export')
        self.file(pm.DATA + '/bin/portmaster-ui-start.sh', 'old wrapper')
        self.inst.install()
        self.assertFalse(export.exists())
        saved = list((self.inst.base / 'backups').glob('*/exports/share/custom'))
        self.assertEqual(saved[0].read_text(), 'preserve export')

    def test_gist_profile_migration(self):
        self.file(pm.PROFILE, 'XDG_DATA_DIRS=/var/lib/portmaster/bin/exports/share:$XDG_DATA_DIRS\n')
        self.inst.install()
        self.assertIn('export XDG_DATA_DIRS=', self.inst.path(pm.PROFILE).read_text())
        self.assertTrue(list((self.inst.base / 'backups').glob('*/zzz-portmaster-to-xdg-data-dirs.sh')))

    def test_unknown_bin_directory_fails_before_download(self):
        self.inst.path(pm.DATA + '/bin/custom').mkdir(parents=True)
        with self.assertRaisesRegex(RuntimeError, 'Unexpected directory'):
            self.inst.install()
        self.assertFalse(self.calls)

    def test_missing_library_fails_before_stop(self):
        self.fail = lambda a: a[0] == 'ldd'
        with self.assertRaisesRegex(RuntimeError, 'libraries unavailable'):
            self.inst.install()
        self.assertFalse(any(a[:2] == ('systemctl', 'stop') for a in self.calls))

    def test_repair_restores_executable_modes(self):
        self.inst.install()
        core = self.inst.path(pm.DATA + '/bin/portmaster-core')
        core.chmod(0o644)
        self.inst.install()
        self.assertEqual(core.stat().st_mode & 0o777, 0o755)

    def test_partial_newer_version_is_not_downgraded(self):
        self.inst.install()
        self.inst.path(pm.DATA + '/bin/portmaster-core').unlink()
        self.inst.path(pm.DATA + '/bin/index.json').write_text('{"Version":"99.0.0"}')
        self.calls.clear()
        with self.assertRaisesRegex(RuntimeError, 'different version'):
            self.inst.install()
        self.assertFalse(any(a[0] == 'curl' for a in self.calls))

    def test_repair_label_failure_restores_firewall_and_can_retry(self):
        self.inst.install()
        self.inst.enable()
        self.fail = lambda a: a[0] == 'restorecon'
        with self.assertRaises(subprocess.CalledProcessError):
            self.inst.install()
        self.assertIn('firewalld.service', self.active)
        self.assertNotIn('portmaster.service', self.active)
        self.fail = None
        self.inst.install()
        self.inst.enable()
        self.assertIn('portmaster.service', self.active)

    def test_uninstall_label_failure_retains_management_for_retry(self):
        self.inst.install()
        self.fail = lambda a: a[:3] == ('semanage', 'fcontext', '-d')
        with self.assertRaises(subprocess.CalledProcessError):
            self.inst.uninstall()
        self.assertTrue((self.inst.base / 'manage').exists())
        self.fail = None
        self.inst.uninstall()

    def test_existing_selinux_rules_are_not_removed(self):
        self.labels.update(pm.LABELS)
        self.inst.install()
        self.inst.uninstall()
        self.assertEqual(self.labels, set(pm.LABELS))


class Integration(unittest.TestCase):
    def test_unit_relabels_before_start_and_cleanup(self):
        unit = (SOURCE / 'portmaster.service').read_text()
        self.assertLess(unit.index('ExecStartPre=/usr/sbin/restorecon'), unit.index('ExecStart='))
        self.assertLess(unit.index('ExecStopPost=/usr/sbin/restorecon'),
                        unit.index('ExecStopPost=-/var/lib/portmaster/bin/portmaster-core recover-iptables'))
        self.assertIn('--bin-dir=/var/lib/portmaster/bin', unit)
        self.assertNotIn('RestartPreventExitStatus=24', unit)

    def test_launcher_preserves_arguments(self):
        # Replace only the absolute payload path, execute the actual shell wrapper.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            payload = path / 'payload'
            payload.write_text('#!/usr/bin/python3\nimport sys,json\nprint(json.dumps(sys.argv[1:]))\n')
            payload.chmod(0o755)
            wrapper = path / 'wrapper'
            wrapper.write_text((SOURCE / 'portmaster-ui').read_text().replace(
                '/var/lib/portmaster/bin/portmaster', str(payload)))
            result = subprocess.run(['sh', str(wrapper), '--background', 'a b', '$literal'],
                                    check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), ['--background', 'a b', '$literal'])

    def test_profile_is_idempotent_and_exported(self):
        profile = SOURCE / 'portmaster-path.sh'
        result = subprocess.run(['sh', '-c', '. "$1"; . "$1"; env', 'sh', str(profile)],
                                env={'PATH': '/usr/bin:/bin'}, capture_output=True, text=True, check=True)
        self.assertIn('XDG_DATA_DIRS=/var/lib/bazzite-dx/portmaster/share:/usr/local/share:/usr/share\n',
                      result.stdout)

    def test_dx_recipe_is_imported(self):
        stage = (ROOT / 'build_files/stages/08-services.sh').read_text()
        self.assertIn('import "/usr/share/ublue-os/just/95-bazzite-dx.just"', stage)
        self.assertIn('grep -Fxq "$dx_just_import"', stage)

    def test_no_image_installation_or_activation(self):
        for path in (ROOT / 'build_files').rglob('*.sh'):
            self.assertNotIn('portmaster', path.read_text())
        self.assertFalse((ROOT / 'system_files/etc/systemd/system/portmaster.service').exists())
        self.assertFalse((ROOT / 'system_files/usr/lib/systemd/system/portmaster.service').exists())
        self.assertTrue(os.access(SCRIPT, os.X_OK))


if __name__ == '__main__':
    unittest.main()

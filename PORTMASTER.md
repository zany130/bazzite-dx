# Optional Portmaster on Bazzite-DX

The image includes a small installer and templates, **not Portmaster binaries or an enabled
service**. There are no build-time downloads, new packages, RPM layers, sysexts, boot hooks,
or changes to SELinux enforcement. This integration currently supports x86_64 Portmaster v2.

## Use

Run `ujust install-portmaster` for the action picker, or use these explicit actions:

- `ujust install-portmaster install`: download and verify the reviewed bootstrap if needed,
  install integration, leave a **new** service disabled. Log out/in to refresh the app menu.
- `ujust install-portmaster repair`: same idempotent operation; preserve an existing service's
  enabled state and restart it only if it was running. Close the UI before repairing.
- `ujust install-portmaster enable`: confirm the firewall switch, enable/start Portmaster,
  and install background UI autostart for subsequent desktop logins.
- `ujust install-portmaster disable`: stop/disable Portmaster, recover its iptables chains,
  remove UI autostart, and restore the firewalld state recorded at enable time. Run repair
  first to migrate a legacy Gist installation.
- `ujust install-portmaster status`: view service status without administrator privileges.
- `ujust install-portmaster uninstall`: disable and remove owned integration and SELinux
  rules; **retain settings, databases, downloaded binaries/intelligence, and backups**.

Open Portmaster from the application menu, or run
`/var/lib/bazzite-dx/portmaster/portmaster-ui`. Check that core initialization and initial
intelligence downloads finish before relying on filtering. Starting a service successfully
is not a test that filtering is working. Application upgrades still require Portmaster's
normal confirmation/restart; intelligence updates remain automatic. Existing update/channel
preferences are never overwritten.

Enabling Portmaster explicitly replaces firewalld, following upstream's service conflict.
The installer records firewalld's previous active/enabled states before changing them and
restores them on disable/uninstall or failed enable. It refuses unusual enablement states
rather than guessing. A firewall switch/restart is not a guarantee of uninterrupted filtering;
perform first installation/repair while sensitive network activity is paused. The integration
cannot reconstruct firewalld's state from before an older Gist installation.

## Layout and update behavior

- `/var/lib/portmaster/bin`: **only upstream payload and index files**. The native updater
  owns this directory and can replace every entry.
- `/var/lib/portmaster`: existing configuration, databases, logs, intel, and native update
  staging/rollback directories. Data does not move during migration.
- `/var/lib/bazzite-dx/portmaster`: independent launcher, XDG share directory, management
  helper/templates, ownership ledger, and private migration/recovery backups.
- `/etc/systemd/system/portmaster.service`: direct core execution with explicit writable
  `--bin-dir`, `--data-dir`, and log paths. No wrapper between PID 1 and the core.
- `/etc/profile.d/zzz-portmaster-to-xdg-data-dirs.sh`: idempotently **exports** the persistent
  integration share path with default XDG directories when unset. No system-wide writable
  `/usr` assumptions. A fresh login is necessary for desktop processes to inherit this change.
- `/etc/xdg/autostart/portmaster-autostart.desktop`: created only by explicit enable.

Persistent `semanage fcontext` rules label only the two executable files and the separate
launcher `bin_t`. The integration does not label databases or the entire data tree as executable.
Every systemd start restores labels on the core and UI; stop cleanup relabels the core before
calling `recover-iptables` because the updater may already have replaced it. A failure to
restore labels before starting is fatal, not silently suppressed. Existing SELinux rules
are not claimed/removed, and conflicting exact rules fail visibly. No policy allow rules,
booleans, permissive domains, `setenforce`, or sandbox-disabling flags are added.

Core's in-app restart uses `systemctl restart portmaster`; its native signed updater remains
unchanged. No timer, second updater, or build-time release download competes with it. The UI
wrapper uses `exec` and forwards `"$@"` at launch time; no permanent WebKit compositing workaround
is forced. For a particular GPU problem, test `WEBKIT_DISABLE_COMPOSITING_MODE=1` explicitly.
Older upstream UI relaunch bugs may still require closing/reopening the UI after an update.

## Bootstrap and prerequisites

`system_files/usr/share/bazzite-dx/portmaster/bootstrap.json` is the **unmodified** upstream
stable v3 manifest for 2.2.9, reviewed on 2026-11-20. Its four applicable Linux/shared payloads
are downloaded from their versioned HTTPS URLs and checked against the committed SHA256 values
before activation. The full index (including its signature and other-platform artifacts) is
preserved for Portmaster. Initial trust is the reviewed repository checksum pin plus HTTPS;
the installer does not independently verify the manifest signature. Native subsequent updates
use Portmaster's own trust store. No downloaded bootstrap utility is run as root.

Maintainers should review a newer upstream manifest and update the whole file when refreshing
the bootstrap, then verify the four checksums and repeat VM acceptance. Do not edit individual
fields in a signed index. Healthy existing installations are verified against the payload hashes
in their installed index and are never downgraded to the bootstrap. An incomplete installation
whose index has a different version, or whose existing binaries have no valid index, is refused
until a matching reviewed bootstrap is available, instead of risking an implicit downgrade against
newer data.

Python 3, curl, systemd, `ldd`, `semanage`, and `restorecon` are required. The desktop binary needs
GTK3/WebKitGTK 4.1 and its dependencies. The installer checks actual UI library resolution before
stopping an existing service. Missing tools/libraries produce an actionable failure; **no host
package installation is attempted**. On Fedora, `semanage` is provided by
`policycoreutils-python-utils`, and WebKitGTK 4.1 by `webkit2gtk4.1`. If a future base drops them,
review its package composition rather than adding automatic host layering. Successful `ldd`
does not verify dynamically loaded tray libraries or real KDE/Wayland rendering.

## Gist migration and failures

The known Gist service, profile fragment, and autostart are recognized by exact checksums in
`legacy.json`, derived from Gist revision `0fbf9d9c846060a2b7879327bab621db67880123` (empty original
installer arguments/environment). Customized versions are refused for manual inspection.
Existing systemd drop-ins are retained. RPM-managed or v1 installations are not silently adopted.

Repair moves `bin/exports`, `bin/portmaster-ui-start.sh`, and leftover `updatemgr*` files into
private backup directories outside the updater area; it does not delete their contents.
Other unexpected files/directories, symlinked privileged paths, or writable/untrusted executable
paths cause a failure. Standard data/configuration stays in place. A corrupt/missing payload
with a matching bootstrap version is downloaded into a separate directory on the destination
filesystem before the old binary directory is backed up and replaced. Checksum/download/library
failures leave a running service untouched. Mutations are serialized against other installer
invocations; after staging, the core is stopped and the installed index/payloads are checked again
before replacement so an update that completed during download is preserved.

Failures after the service stops are reported and keep repair state/backups. If this integration
previously took over firewalld, it restores that recorded state on repair failure. This is not a
full transaction rollback and does not promise to restart a broken legacy installation. Fix the
reported problem, rerun repair, check status, and explicitly enable again if necessary. Do not
run the old Gist concurrently. The retained management copy lets repair/removal continue after
rebasing to an image without the recipe:

```sh
sudo /var/lib/bazzite-dx/portmaster/manage uninstall
```

Rebases must still provide systemd, Python, SELinux tools/policy, and compatible UI libraries.
Data persists, but compatibility with arbitrary distributions is not promised. Reinstalling
from a later DX image updates the integration templates without replacing native-updated binaries.

Uninstall closes the service, not every user's UI process: close the UI yourself. It removes only
recognized integration files/rules; modified files are refused before any removal. The management
helper, its resource templates, and a reduced ownership ledger remain available for retrying
removal after a rebase. Empty integration directories and private backups may remain. After
successful uninstall and exporting anything you
want to keep, **deliberately deleting** `/var/lib/portmaster` removes profiles, history, settings,
intel, and binaries; deleting `/var/lib/bazzite-dx/portmaster` also deletes recovery backups.
Neither deletion is automatic. User-owned desktop shortcuts/autostart overrides are not edited.

## Audit evidence

The [Gist and comments](https://gist.github.com/zany130/ba610a7391fcee4e4e7a20cbd06bc754)
and [upstream issue #2309](https://github.com/safing/portmaster/issues/2309) document two distinct
classes of failures: read-only binary targets and this script's updater-owned integration.

- Upstream [upgradeMoveFiles](https://github.com/safing/portmaster/blob/e9ca8c4585906aabc6058f83841e11aaf9c00f43/service/updates/upgrade.go)
  moves **all** entries out of the binary directory. The Gist's launcher disappears; its exports
  directory fails when a cross-filesystem move falls back to a file copy (the reported “is a
  directory” error). Keeping only upstream payload there fixes both integration conflicts.
- The Gist's fcontext expression matches the `bin` directory, not `bin/portmaster-core`.
  `chcon` is temporary; replacement inodes can bring other labels. The `|| :1` typo is not a
  valid error-suppression command. Comments reporting success after `chcon` are consistent with
  this labeling defect, but do not prove every startup failure is SELinux-related.
- [Update configuration](https://github.com/safing/portmaster/blob/e9ca8c4585906aabc6058f83841e11aaf9c00f43/service/config.go)
  stages under data and targets the configured binary directory. It already attempts core
  relabeling, but ignores failure. Explicit fcontext rules and service-boundary restoration cover
  updates, older cores, reboots, and relabels without changing the native update mechanism.
- [Linux service restart](https://github.com/safing/portmaster/blob/e9ca8c4585906aabc6058f83841e11aaf9c00f43/cmds/cmdbase/service_linux.go)
  calls systemd; XDG_DATA_DIRS does **not** control systemd's unit search path. The new service is
  consistently installed, daemon-reloaded, and directly executes the core. It does not carry the
  Gist's unexplained restart-prevention exit code or memory reservation.
- The Gist expands `"$@"` while creating its launcher rather than at launch, doesn't create the
  icon directory, creates a non-repeatable symlink, and can download `updatemgr.1` while executing
  an older `updatemgr`. These paths are eliminated. Missing WebKit libraries and duplicate/black
  UI windows from the comments are separate issues, not evidence that core filtering failed.

The recipe follows the existing DX `95-bazzite-dx.just` layout and Bazzite's
[ugum action-picker conventions](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/share/ublue-os/just/87-bazzite-framegen.just).

## Validation

Run the unprivileged regression suite:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
shellcheck system_files/usr/share/bazzite-dx/portmaster/{portmaster-ui,portmaster-path.sh}
just --unstable --fmt --check -f system_files/usr/share/ublue-os/just/95-bazzite-dx.just
```

The tests exercise real temporary filesystem installation, repeat/repair, modeled whole-directory
self-updates, Gist export/profile migration, checksum/network/library failures, firewall state
restoration, removal/reinstall, unsafe/customized paths, argument forwarding, and persistent files
across modeled reboot/rebase. Commands that touch systemd, SELinux, or the network are mocked.
They do **not** demonstrate a real enforcing-SELinux installation, a real upgrade, reboot, rebase,
or filtering under traffic. All four pinned payload checksums and core `version` were verified
locally; UI linked libraries resolved. No privileged installer or service was run on the host.

### Disposable Bazzite-DX VM acceptance (required before treating this as production-validated)

1. Boot a built PR image with SELinux **enforcing** and working networking. Verify no Portmaster
   unit, payload, or autostart was installed by the image. Record firewalld status/enablement.
2. Run install; check SHA256 against the bootstrap, desktop after a new login, and that core is
   still disabled. Run install again: no binary downloads, no settings loss. Then enable and
   verify core logs, API/UI connection, initial intel download, and a test allow/block rule.
3. Snapshot the VM, create a test profile, and apply a genuine upstream binary update through
   the UI when a newer signed release exists. Check the version, core PID/restart, UI reopening,
   `ls -Z /var/lib/portmaster/bin/{portmaster,portmaster-core}`, and the same allow/block behavior.
   Confirm no integration entries appear in bin/. Check hourly intel updates independently.
4. Inspect `journalctl -u portmaster.service -b` and `sudo ausearch -m AVC,USER_AVC -ts boot`.
   Do not generate broad allow policies or disable SELinux to make this pass. Validate cleanup
   and restart after a forced core failure in the VM, including no stale Portmaster chains.
5. Reboot; confirm enabled service, labels, settings, filtering, and one UI per login. Rebase to
   a second DX build; repeat. Rebase to a compatible base lacking the recipe and verify the
   persistent helper can disable/uninstall. A modeled test alone is not a passing rebase gate.
6. Test repair from a snapshot of the old Gist installation, including exports/launcher leftovers
   and a stopped core after update. Verify backups and settings, labels, daemon reload, native
   update, reboot, and UI. Test customized service refusal before service interruption.
7. Disable and uninstall twice; check core is stopped, enablement/autostart/menu integration
   removed after a new login, only owned fcontext rules removed, no stale Portmaster firewall
   rules, and recorded firewalld behavior restored. Reinstall and confirm saved profiles remain.
8. Test interrupted downloads, full disk, unavailable SELinux tools, and missing WebKit in a VM.
   A failure must remain visible, preserve data/backups, and permit repair. Record actual results
   and AVCs in the PR; do not mark this checklist passed based on the mocked suite.

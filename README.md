# bazzite-dx

Custom [Bazzite-DX](https://github.com/ublue-os/bazzite) with additional packages and automation.

## Quick Start

```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```

## Additional Packages

Base: `ghcr.io/ublue-os/bazzite-dx:latest`

**System:** cockpit, cockpit-machines, cockpit-ostree, cockpit-ws-selinux, cockpit-file-sharing, cockpit-nspawn, coolercontrol  
**Desktop:** kvantum, plasma-discover (minimal), kwin-effect-roundcorners  
**Hardware:** solaar, liquidctl, arctis-sound-manager, kcast  
**Storage:** btfs, megasync, dolphin-megasync  
**Boot/Security:** beep, rEFInd, rEFInd-tools, sbctl, google-authenticator  
**Remote:** waypipe  
**Media:** vlc (+ all plugins), python3-pygame  
**Deck:** Steam Deck bootstrap/session configs re-enabled, custom SDDM themes, auto-login

COPR repos enabled for additional packages: `agundur/KCast` (for `kcast`), `matinlotfali/KDE-Rounded-Corners`, `loteran/arctis-sound-manager`.

Deck-specific behavior is intentionally restored on top of the DX base image in
`build_files/build.sh` by re-adding `bootstrap_steam.tar.gz` and
`virtualkbd.conf`, reinstalling `steamos-manager-powerstation`, removing the
desktop-login replacements (`ds-inhibit`, `plasma-login-manager`), re-enabling
`sddm.service`, and restoring the KDE restriction keys expected by the Deck
session flow. Upstream Bazzite no longer keeps `steamos.conf` as a static repo
file; it is now provided by the Deck session stack, while
`zz-steamos-autologin.conf` is still managed dynamically at runtime.

## Boot Chime

PC speaker beep at startup (1000Hz, 1500Hz, 1700Hz). Disable with:
```bash
sudo systemctl disable beep-startup.service
```

## Gamescope Background Apps

Background applications run invisibly under Xvfb during the Gamescope/Steam session. Each application is independently supervised by systemd through `gamescope-app@.service`, while `gamescope-apps.target` groups their lifecycle with the Gamescope session.

Packaged app definitions live in `/etc/gamescope/apps.d/`. A user definition with the same app name in `~/.config/gamescope/apps.d/` takes precedence.

Example user app:

```bash
mkdir -p ~/.config/gamescope/apps.d
cat > ~/.config/gamescope/apps.d/openrgb.conf <<'EOF'
COMMAND=(
    openrgb
    --startminimized
)
EOF

systemctl --user enable gamescope-app@openrgb.service
```

The instance name deliberately matches the app, making its status and logs immediately identifiable:

```bash
systemctl --user status gamescope-app@discord.service
journalctl --user -u gamescope-app@discord.service -f
systemctl --user restart gamescope-app@discord.service
systemctl --user disable --now gamescope-app@discord.service
```

Packaged defaults are `gamescope-app@megasync.service` and `gamescope-app@discord.service`. Either can be disabled independently with `systemctl --user mask gamescope-app@APP.service`.

To disable every Gamescope background app:

```bash
touch ~/.config/gamescope/disable-apps
```

Remove the flag and restart the Gamescope session to enable the target again. See [`GAMESCOPE_APPS.md`](GAMESCOPE_APPS.md) for configuration, migration, and debugging details.

## LG Buddy

Controls LG WebOS TV at boot/shutdown/sleep. Not enabled by default - requires setup.

**Components:** systemd service, startup/shutdown scripts, sleep hook

**Setup:**
1. Install alga: `brew install pipx`, then `pipx install alga` (may need to restart shell)
2. Pair TV: `alga tv add <identifier> [TV_IP]`
3. Edit files, replace `zany130` with your username:
   - `/usr/local/bin/LG_Buddy_Startup` - Set `TV_INPUT="HDMI_1"` (find options with `alga input list`)
   - `/usr/local/bin/LG_Buddy_Shutdown`
   - `/usr/lib/systemd/system-sleep/lg-buddy-sleep`
   - `/etc/systemd/system/LG_Buddy.service` - Update `User=` and `Group=`
4. Enable: `sudo systemctl daemon-reload && sudo systemctl enable --now LG_Buddy.service`

**Behavior:** TV powers on/switches input at boot/wake, powers off at shutdown/sleep (not reboot)

**Logs:**
```bash
journalctl -u LG_Buddy.service -f
journalctl -t lg-buddy-sleep -f
```

## Video Port Reset

Triggers display hotplug events to fix detection issues. Passwordless sudo enabled.

```bash
# List connectors
sudo reset-video-port --list

# Reset port
sudo reset-video-port 1 DP-2
sudo reset-video-port 0000:03:00.0 DP-2
```

Use cases: display not detected, black screen on wake, resolution/VRR issues

## Waypipe

Run Wayland GUI apps over SSH (like X11 forwarding but for Wayland).

**Basic usage:**
```bash
waypipe ssh user@host application
waypipe ssh user@host firefox
```

**Performance tuning:**
```bash
waypipe --compress zstd ssh user@host app  # slower network
waypipe --compress none ssh user@host app  # faster network
```

Requires waypipe on both systems. Debug with: `waypipe -d ssh user@host app`

## Config Changes

- Custom SSH, Polkit, sudoers rules
- Custom Topgrade config

---

## Building (Template Info)

Based on [Universal Blue image-template](https://github.com/ublue-os/image-template).

**Key files:**
- `Containerfile` - Image build definition
- `build_files/build.sh` - Package installation
- `.github/workflows/build.yml` - CI/CD
- `Justfile` - Local build commands (run `just --list`)

**Local build:** `just build`  
**Switch to custom image:** `sudo bootc switch ghcr.io/<user>/<image>:latest`

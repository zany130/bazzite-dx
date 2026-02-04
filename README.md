# bazzite-dx

Custom [Bazzite-DX](https://github.com/ublue-os/bazzite) with additional packages and automation.

## Quick Start

```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```

## Additional Packages

Base: `ghcr.io/ublue-os/bazzite-dx:latest`

**System:** cockpit, cockpit-ostree, cockpit-file-sharing, coolercontrol  
**Desktop:** kvantum, plasma-discover (minimal), kwin-effect-roundcorners, wallpaper-engine-kde-plugin  
**Hardware:** solaar, liquidctl, HeadsetControl, HeadsetControl-Qt  
**Storage:** btfs, megasync, dolphin-megasync  
**Boot/Security:** beep, rEFInd, rEFInd-tools, sbctl, google-authenticator  
**Remote:** waypipe  
**Media:** vlc (+ all plugins), python3-pygame  
**Deck:** Steam Deck configs re-enabled, custom SDDM themes, auto-login

## Boot Chime

PC speaker beep at startup (1000Hz, 1500Hz, 1700Hz). Disable with:
```bash
sudo systemctl disable beep-startup.service
```

## Gamescope Background Apps

Config-driven auto-launch for apps in Gamescope/Steam session. Runs via xvfb-run (invisible background).

**Config files** (user override takes precedence):
- `/etc/gamescope-apps.conf` (system default)
- `~/.config/gamescope/apps.conf` (user override)

**Format:** One command per line, `#` for comments
```bash
megasync
flatpak run com.discordapp.Discord --start-minimized
# pcloud
# openrgb --startminimized
```

**Management:**
```bash
# Status/logs
systemctl --user status gamescopeApps.service
journalctl --user -u gamescopeApps.service -f

# Restart after config changes
systemctl --user restart gamescopeApps.service

# Disable
touch ~/.config/gamescope/disable-apps
# or: systemctl --user mask gamescopeApps.service
```

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

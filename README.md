# Bazzite DX

[![Build container image](https://github.com/zany130/bazzite-dx/actions/workflows/build.yml/badge.svg)](https://github.com/zany130/bazzite-dx/actions/workflows/build.yml)

My custom [Bazzite](https://bazzite.gg/) image, combining Steam Game Mode and the KDE Plasma desktop with development tools, containers, virtualization, and a collection of personal hardware and desktop customizations.

The goal is a gaming PC that can also serve as a development workstation, with the tools built into the image instead of added through local package layering.

## Current status

**Functional and evolving.** This is a personal image with opinionated defaults and some features tailored to my setup. It is an independent customization of Bazzite, not an official Bazzite edition.

| | Current configuration |
| --- | --- |
| Base image | `ghcr.io/ublue-os/bazzite-deck:stable`, pinned by digest |
| Published image | `ghcr.io/zany130/bazzite-dx:latest` |
| Desktop and gaming sessions | KDE Plasma and Steam Game Mode from the Bazzite Deck base |
| Build system | Universal Blue image-template, Podman, and GitHub Actions |

The `latest` tag is this project's output tag; it does not mean the image tracks Bazzite's testing channel. See the [Containerfile](Containerfile) for the exact base and the [build workflow](https://github.com/zany130/bazzite-dx/actions/workflows/build.yml) for build results.

## Switch to this image

From an existing, compatible bootc installation:

```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```

This stages the image for the next boot. These commands switch an existing system; they are not a fresh-install procedure.

## What's included

Alongside the Bazzite Deck base, this image adds the following tools and customizations. The [build script](build_files/build.sh) is the source of truth for additional packages.

| Area | Highlights |
| --- | --- |
| Development and debugging | Android tools, Flatpak Builder, ccache, git-subtree, BCC, bpftrace, bpftop, sysprof, and tiptop |
| Containers | Docker CE with Compose and Buildx, Podman Machine, and Podman TUI |
| Virtual machines | QEMU/KVM, libvirt, native virt-manager, guestfs-tools, virtiofsd, swtpm, and AArch64 user-mode emulation |
| System administration | Cockpit, machine and OSTree integration, plus file sharing, file navigation, benchmarking, hardware probe, diagnostics, and nspawn extensions |
| Compute | Ramalama and ROCm HIP, OpenCL, and diagnostic tools |
| Remote access and backups | Waypipe, Mosh, rclone, restic, and Nmap |
| Hardware | CoolerControl, liquidctl, Solaar, and Arctis Sound Manager |
| Desktop and media | Kvantum, rounded KWin corners, mpv, CDEmu/gCDEmu, and Tesseract OCR with English and Spanish language data |
| Storage and sync | MEGAsync, Dolphin integration for MEGAsync, and BTFS |
| Boot and authentication | rEFInd tools, sbctl, Google Authenticator PAM support, and a PC speaker startup chime |

Kate, KWrite, and KFind are removed by the build. The repository also includes VS Code settings and extension setup hooks; these expect the `code` command to be available.

### Services and setup

Docker, Podman, and the modular libvirt sockets are enabled during the build. Installing a package does not mean every related service is enabled or configured: Cockpit is included, but this repository does not explicitly enable `cockpit.socket`.

The image also ships virtualization setup helpers:

```bash
ujust setup-virtualization help
```

Extra fonts can be installed through the included Homebrew bundle:

```bash
ujust install-fonts
```

## Game Mode features

### Choose the default session

Use the included helper to select Steam Game Mode or the desktop as the SDDM autologin session:

```bash
ujust toggle-gamemode
```

Or choose directly:

```bash
ujust toggle-gamemode gamemode
ujust toggle-gamemode desktop
ujust toggle-gamemode status
```

The selection takes effect at the next login or reboot.

### Background applications

Applications can run in the background under Xvfb while the Gamescope session is active. Each app has its own systemd user service, logs, and restart handling. The group stops when Game Mode ends or Plasma starts.

MEGAsync and Discord are the packaged defaults. The Discord definition expects the `com.discordapp.Discord` Flatpak to be installed separately.

```bash
# Inspect an app
systemctl --user status gamescope-app@discord.service
journalctl --user -u gamescope-app@discord.service -f

# Stop and disable a packaged default
systemctl --user mask --now gamescope-app@discord.service

# Restore it for the next Game Mode session
systemctl --user unmask gamescope-app@discord.service
```

To prevent the app group from starting in subsequent Game Mode sessions:

```bash
mkdir -p ~/.config/gamescope
touch ~/.config/gamescope/disable-apps
```

Remove that file and restart the Gamescope session to allow the group to start again.

Custom app definitions go in `~/.config/gamescope/apps.d/`. A user definition overrides a packaged definition with the same name. See [Gamescope background applications](GAMESCOPE_APPS.md) for examples, migration instructions, and troubleshooting.

### Nested Steam Game Mode

The **Nested Steam Gamemode** application launcher, also available as `gamemode-nested`, starts Steam's Game Mode interface in a Gamescope window from the desktop.

This is an experimental convenience feature with limitations. It restarts Steam, does not reproduce every feature of a full Game Mode session, and requires closing Steam through its tray icon to exit.

## Updates

Run:

```bash
ujust update
```

The included recipe runs Topgrade with this image's configuration to update the system and supported tools you have installed, including Flatpaks, Distrobox containers, Homebrew packages, and selected language package managers. It also includes a custom Plasmoid update command.

To invoke the same configuration directly:

```bash
topgrade --config /etc/ublue-os/topgrade.toml --keep
```

The enabled updater list lives in [topgrade.toml](system_files/etc/ublue-os/topgrade.toml). Not every updater applies to every system, and configured commands require their corresponding tools to be installed.

## Hardware and desktop helpers

### LG Buddy

LG Buddy provides scripts for controlling an LG webOS TV alongside the PC: power on and select an input at startup, power off at shutdown, and coordinate power state around sleep and wake. The shutdown script leaves the TV on during a reboot.

**This integration is specific to my setup and needs customization before use.** It expects a paired [alga](https://github.com/Tenzer/alga) installation at `/home/zany130/.local/bin/alga` and uses `HDMI_1` by default.

The relevant files are:

| File in the image | Purpose |
| --- | --- |
| `/usr/libexec/LG_Buddy_Startup` | Startup commands, username, and TV input |
| `/usr/libexec/LG_Buddy_Shutdown` | Shutdown commands and username |
| `/usr/lib/systemd/system-sleep/lg-buddy-sleep` | Sleep/wake commands, username, and TV input |
| `/etc/systemd/system/LG_Buddy.service` | Service user, group, and script paths |

For a custom build, update these files under [`system_files/`](system_files/) to match your account and TV. Files under `/usr` are image-managed; they are not ordinary editable configuration files on the running system.

The boot/shutdown service is not enabled by the build. Once alga is installed, paired, and the paths and account settings match your system, enable it with:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now LG_Buddy.service
```

The sleep hook is installed independently of the service and can run whenever its expected alga executable exists. Disabling the service alone does not disable that hook.

Logs are available with:

```bash
journalctl -u LG_Buddy.service -b
journalctl -t lg-buddy-sleep -b
```

### Display connector reset

The `reset-video-port` helper triggers a display connector hotplug event. It can be useful when troubleshooting display detection or wake problems; it is not a guaranteed fix for driver or VRR issues.

```bash
# List connectors
sudo reset-video-port --list

# Reset a connector by card number or PCI address
sudo reset-video-port 1 DP-2
sudo reset-video-port 0000:03:00.0 DP-2
```

### Startup chime

A PC speaker chime is enabled by default. Hardware without a PC speaker may not produce a sound.

To disable it:

```bash
sudo systemctl disable beep-startup.service
```

### Wayland apps over SSH

Waypipe is included for forwarding Wayland applications over SSH. It needs to be installed on both systems:

```bash
waypipe ssh user@host application
```

## Authentication and permissions

This image includes personal policy changes worth reviewing before adopting it:

- [SSH configuration](system_files/etc/ssh/sshd_config.d/99-bazzite.conf) disables the SSH password authentication method and allows public-key or PAM keyboard-interactive authentication. The accompanying [PAM configuration](system_files/etc/pam.d/sshd) includes Google Authenticator and the system password-auth stack; this is not a mandatory key-plus-OTP policy.
- A [sudoers rule](system_files/etc/sudoers.d/1-AllowScripts) allows members of `wheel` to run `reset-video-port` without a password.
- A [Polkit rule](system_files/etc/polkit-1/rules.d/90-plugin-loader.rules) permits members of `wheel` to start and stop `plugin_loader.service` without an authentication prompt.
- The [privileged setup hook](system_files/usr/share/ublue-os/privileged-setup.hooks.d/20-dx.sh) adds members of `wheel` to the Docker group when the hook runs.

## Build and customize

This project uses the [Universal Blue image-template](https://github.com/ublue-os/image-template).

| Path | Purpose |
| --- | --- |
| [`Containerfile`](Containerfile) | Base image, file overlay, permissions, and image validation |
| [`build_files/build.sh`](build_files/build.sh) | Additional packages, repositories, and service defaults |
| [`system_files/`](system_files/) | Files installed into the image |
| [`image-template.env`](image-template.env) | Image name, metadata, and default tag |
| [`Justfile`](Justfile) | Local build, lint, and disk-image helpers |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | Container builds, publishing, and signing |

With `just`, Podman, and `jq` installed, build from the repository root:

```bash
just build
```

Use `just --list` to see the available build and disk-image commands. When making your own fork, update the image metadata and publishing configuration, and configure `SIGNING_SECRET` for the signing step. See the upstream template for the full setup guide.

The build locks Qt 6 and Plasma packages during customization and selectively enables third-party repositories for package installation to reduce unintended changes to the base desktop stack.

## Feedback and upstream projects

Report issues with this image's additions or configuration in [this repository](https://github.com/zany130/bazzite-dx/issues). Include your image version, relevant logs, and whether the problem also occurs on upstream Bazzite when known.

Thanks to [Bazzite](https://github.com/ublue-os/bazzite), [Universal Blue](https://universal-blue.org/), and the developers of the tools included here.

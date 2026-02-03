# bazzite-dx

This is a customized version of [Bazzite-DX](https://github.com/ublue-os/bazzite) (Developer Experience) with additional tools, packages, and automation specifically tailored for a gaming PC setup with LG WebOS TV integration.

## Quick Start

If you're already on a Universal Blue or Bazzite system, you can switch to this image with:

```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```

After switching, configure [LG Buddy](#lg-buddy-setup) if you have an LG WebOS TV, check out the [Video Port Reset](#video-port-reset) tool if you experience display issues, and see [Waypipe](#waypipe---remote-gui-applications) for running GUI applications remotely over SSH.

## Changes vs Upstream Bazzite

This custom image extends the base `ghcr.io/ublue-os/bazzite-dx:latest` image with the following modifications:

### Additional Packages

**System Management & Monitoring:**
- `cockpit` - Web-based system management interface
- `cockpit-ostree` - OSTree/bootc management
- `cockpit-file-sharing` - File sharing management (from 45Drives)
- `coolercontrol` - Hardware cooling control

**Desktop & Utilities:**
- `kvantum` - Qt theme engine
- `plasma-discover` - KDE package discovery (minimal install, for plasmoid packages only)
- `kwin-effect-roundcorners` - Rounded window corners for KDE
- `wallpaper-engine-kde-plugin` - Wallpaper Engine support

**Hardware & Peripherals:**
- `solaar` - Logitech device manager
- `liquidctl` - Liquid cooling control
- `HeadsetControl` & `HeadsetControl-Qt` - USB headset control

**File Systems & Storage:**
- `btfs` - BitTorrent filesystem
- `megasync` & `dolphin-megasync` - MEGA cloud storage integration

**Boot & Security:**
- `beep` - Custom PC speaker beeps
- `rEFInd` & `rEFInd-tools` - Boot manager
- `sbctl` - Secure Boot management
- `google-authenticator` - Two-factor authentication

**Remote Access:**
- `waypipe` - Run GUI applications remotely over SSH (Wayland equivalent of X11 forwarding)

**Media & Development:**
- `vlc` & `vlc-plugins-all` - Media player (flatpak version has broken Blu-ray support)
- `python3-pygame` - Python game development

**Deck-Specific Enhancements:**
- Re-enabled Steam Deck-specific configurations
- Custom SDDM themes and virtual keyboard
- Auto-login service enabled

### Retro Chime - Boot Sound

A nostalgic boot chime that plays at startup using the PC speaker (beep program).

**Features:**
- Three ascending tones (1000Hz, 1500Hz, 1700Hz) play at early boot stage
- Non-blocking - won't delay boot or prevent the system from starting
- Automatically enabled by default
- Does not cause boot failures on systems without PC speaker hardware

**How to disable (if desired):**
```bash
sudo systemctl disable beep-startup.service
```

### Gamescope Headless Apps - Background Applications (Config-Driven)

Automatically launches background applications alongside your Gamescope/Steam session. **Ultra-low maintenance**: just edit a simple config file to add/remove apps - no script editing needed!

**Config-File Driven Approach:**
```bash
# System default (shipped in image)
/etc/gamescope-apps.conf

# Your personal override (optional)
~/.config/gamescope/apps.conf
```

**Simple config format** - one command per line:
```
# This is a comment
megasync
flatpak run com.discordapp.Discord --start-minimized
pcloud
openrgb --startminimized
```

**Adding/Removing Apps:**
```bash
# Option 1: Edit system default (in your image fork)
# Edit: system_files/etc/gamescope-apps.conf

# Option 2: Create user override (at runtime)
cp /etc/gamescope-apps.conf ~/.config/gamescope/apps.conf
nano ~/.config/gamescope/apps.conf
systemctl --user restart gamescopeApps.service
```

**What it does:**
- Reads commands from config file(s)
- Launches each via xvfb-run (virtual X11 display)
- Apps run invisibly in background
- Automatic restart on crash (systemd managed)
- Stops when you exit Gamescope or switch to Plasma

**Default Apps (as shipped in /etc/gamescope-apps.conf):**
- **megasync** - MEGA cloud storage sync
- **Discord** (Flatpak) - Chat application (started minimized)

**Commented out (easy to enable):**
- **pCloud** - Cloud storage
- **nextcloud** - Cloud sync
- **OpenRGB** - RGB lighting control

**How to disable:**
```bash
# Disable all apps (flag file)
touch ~/.config/gamescope/disable-apps

# Or disable the service
systemctl --user mask gamescopeApps.service
```

**How to re-enable:**
```bash
# Remove flag
rm ~/.config/gamescope/disable-apps

# Or unmask service
systemctl --user unmask gamescopeApps.service
```

**Management commands:**
```bash
# Check status
systemctl --user status gamescopeApps.service

# View logs (shows which apps were launched)
journalctl --user -u gamescopeApps.service -f

# Restart (after config changes)
systemctl --user restart gamescopeApps.service
```

**Why config-driven:**
- ✅ **Ultra-low maintenance** - just edit a text file
- ✅ **No script editing** required
- ✅ **No code changes** to add/remove apps
- ✅ **User can override** system defaults
- ✅ **No upstream overrides** - stays aligned with Bazzite

**Implementation details:**
- Systemd user units in `/usr/lib/systemd/user/`
- Drop-in for gamescope-session-plus (doesn't modify upstream)
- Config file approach for maximum flexibility
- Part of immutable image, but user-configurable

**Troubleshooting:**
```bash
# Check if service is running
systemctl --user is-active gamescopeApps.service

# Check what commands are in config
cat /etc/gamescope-apps.conf
cat ~/.config/gamescope/apps.conf  # if exists

# View detailed logs
journalctl --user -u gamescopeApps.service --since today

# Test script manually
/usr/libexec/startGamescopeApps.sh
```

> **Note:** This feature only works in Gamescope/Steam session. Apps do not run in Plasma or other sessions.

### LG Buddy - WebOS TV Automation

A complete automation suite for controlling LG WebOS TVs, including automatic power management and input switching.

**Components:**
- **Systemd Service** (`LG_Buddy.service`) - Controls TV at boot and shutdown (requires manual configuration and enablement)
- **Startup Script** (`LG_Buddy_Startup`) - Powers on TV and switches to the correct input
- **Shutdown Script** (`LG_Buddy_Shutdown`) - Powers off TV (but not on reboot)
- **Sleep Hook** (`lg-buddy-sleep`) - Manages TV state during suspend/resume

> **Note:** The LG_Buddy service is **not enabled by default** because it requires user-specific configuration. See [LG Buddy Setup](#lg-buddy-setup) section below for complete setup instructions.

**Setup Instructions:** See [LG Buddy Setup](#lg-buddy-setup) section below.

### Video Port Reset Tool

A utility script for triggering display port hotplug events to resolve display detection issues.

**Features:**
- Reset individual display ports (DP, HDMI)
- List all available video connectors
- Supports both card numbers and PCI addresses
- Passwordless sudo access for the reset command

**Usage Instructions:** See [Video Port Reset](#video-port-reset) section below.

### Configuration Changes

- Custom SSH configuration
- Custom Polkit rules
- Custom sudoers rules for video port reset
- Custom Topgrade configuration

## LG Buddy Setup

LG Buddy requires the [alga](https://github.com/Tenzer/alga) CLI tool to control your LG WebOS TV.

### Prerequisites

1. **Install pipx (if not already installed):**
   
   Bazzite comes with Homebrew pre-installed, so you can use it to install pipx:
   ```bash
   brew install pipx
   pipx ensurepath
   ```
   
   > **Note:** You may need to restart your terminal or source your shell configuration after running `pipx ensurepath`.

2. **Install alga:**
   ```bash
   pipx install alga
   ```

3. **Pair with your TV:**
   ```bash
   # This will prompt you to accept the connection on your TV
   alga tv add <identifier> [TV_IP_or_hostname]
   ```
   
   > **Note:** If no hostname or IP is provided, alga will default to "lgwebostv," which should work if your TV is discoverable on your network.

### Configuration

Edit the following files to match your setup:

1. **Update username in all scripts and service file** (replace `zany130` with your actual username):
   ```bash
   sudo nano /usr/local/bin/LG_Buddy_Startup
   sudo nano /usr/local/bin/LG_Buddy_Shutdown
   sudo nano /usr/lib/systemd/system-sleep/lg-buddy-sleep
   sudo nano /etc/systemd/system/LG_Buddy.service
   ```
   
   In the scripts, change the line:
   ```bash
   USERNAME="zany130"
   ```
   to:
   ```bash
   USERNAME="<your-username>"
   ```
   
   In the service file (`/etc/systemd/system/LG_Buddy.service`), change:
   ```ini
   User=zany130
   Group=zany130
   ```
   to:
   ```ini
   User=<your-username>
   Group=<your-username>
   ```

2. **Set your TV input** in `/usr/local/bin/LG_Buddy_Startup`:
   ```bash
   TV_INPUT="HDMI_1"  # Change to HDMI_2, HDMI_3, etc. as needed
   ```
   
   To find your input name:
   ```bash
   alga input list
   ```

3. **Reload systemd and enable the service:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now LG_Buddy.service
   ```

### How It Works

- **On Boot/Wake:** TV turns on and switches to your PC's HDMI input
- **On Shutdown/Sleep/suspend:** TV turns off (only on shutdown or sleep/suspend, not reboot)

### Troubleshooting

Check service logs:
```bash
journalctl -u LG_Buddy.service -f
```

Check sleep hook logs:
```bash
journalctl -t lg-buddy-sleep -f
```

## Video Port Reset

The video port reset tool helps resolve display detection issues by triggering a hotplug event on your video connectors.

### Usage

**List available connectors:**
```bash
sudo reset-video-port --list
```

This will show output like:
```
Available connectors:
  1/DP-1
  1/DP-2
  1/HDMI-A-1
```

**Reset a specific port:**
```bash
# Using card number and port name
sudo reset-video-port 1 DP-2

# Using PCI address
sudo reset-video-port 0000:03:00.0 DP-2
```

### Common Use Cases

- Display not detected after boot
- Black screen on monitor wake
- Resolution not switching correctly
- VRR/FreeSync/G-Sync issues

### Automation

Add to your desktop environment's autostart if you need to reset a port on every boot:
```bash
sudo reset-video-port 1 DP-2
```

The command has passwordless sudo access via a sudoers rule so that it won't prompt for a password.

## Waypipe - Remote GUI Applications

Waypipe enables running GUI applications remotely over SSH on Wayland, similar to X11 forwarding but optimized for Wayland compositors.

### Features

- Run Wayland GUI applications over SSH
- Low latency with optimized protocol compression
- Works with any Wayland compositor (KDE Plasma, GNOME, Sway, etc.)
- Automatic clipboard sharing
- Hardware video decoding support

### Prerequisites

Both the local and remote systems should have waypipe installed. This image already includes waypipe.

### Usage

**Basic usage - Run a single application:**
```bash
# From your local machine, connect and run an application
waypipe ssh user@remote-host application-name

# Example: Run Firefox from a remote machine
waypipe ssh user@remote-host firefox
```

**Advanced usage:**

The recommended and supported pattern for most users is `waypipe ssh user@remote-host application-name` as shown above. If you need to integrate waypipe with more complex or existing SSH setups (such as multi-hop connections or custom socket handling), refer to the upstream waypipe documentation for complete, up‑to‑date client/server examples.
**Performance tuning:**
```bash
# Higher compression for slower networks
waypipe --compress zstd ssh user@remote-host application-name

# Lower latency for faster networks
waypipe --compress none ssh user@remote-host application-name
```

### SSH Configuration

For the best experience, ensure your SSH configuration supports compression:
```bash
# In ~/.ssh/config or /etc/ssh/ssh_config
Host remote-host
    Compression yes
    ServerAliveInterval 60
```

### Troubleshooting

If applications fail to start:
1. Verify both systems are running Wayland (not X11)
2. Check that the application supports Wayland
3. Ensure SSH connection is working: `ssh user@remote-host`
4. Try with verbose mode: `waypipe -d ssh user@remote-host application-name`

For more information, see the [waypipe documentation](https://gitlab.freedesktop.org/mstoeckl/waypipe).

---

# Template Information

This repository is based on the [Universal Blue image-template](https://github.com/ublue-os/image-template) for building custom [bootc](https://github.com/bootc-dev/bootc) images.

# Community

If you have questions about this template after following the instructions, try the following spaces:
- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussion forums](https://github.com/bootc-dev/bootc/discussions) - This is not an Universal Blue managed space, but is an excellent resource if you run into issues with building bootc images.

# How to Use

To get started on your first bootc image, simply read and follow the steps in the next few headings.
If you prefer instructions in video form, TesterTech created an excellent tutorial, embedded below.

[![Video Tutorial](https://img.youtube.com/vi/IxBl11Zmq5w/0.jpg)](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Step 0: Prerequisites

These steps assume you have the following:
- A Github Account
- A machine running a bootc image (e.g. Bazzite, Bluefin, Aurora, or Fedora Atomic)
- Experience installing and using CLI programs

## Step 1: Preparing the Template

### Step 1a: Copying the Template

Select `Use this Template` on this page. You can set the name and description of your repository to whatever you would like, but all other settings should be left untouched.

Once you have finished copying the template, you need to enable the Github Actions workflows for your new repository.
To enable the workflows, go to the `Actions` tab of the new repository and click the button to enable workflows.

### Step 1b: Cloning the New Repository

Here I will defer to the much superior GitHub documentation on the matter. You can use whichever method is easiest.
[GitHub Documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository)

Once you have the repository on your local drive, proceed to the next step.

## Step 2: Initial Setup

### Step 2a: Creating a Cosign Key

Container signing is important for end-user security and is enabled on all Universal Blue images. By default the image builds *will fail* if you don't.

First, install the [cosign CLI tool](https://edu.chainguard.dev/open-source/sigstore/cosign/how-to-install-cosign/#installing-cosign-with-the-cosign-binary)
With the cosign tool installed, run inside your repo folder:

```bash
COSIGN_PASSWORD="" cosign generate-key-pair
```

The signing key will be used in GitHub Actions and will not work if it is password protected.

> [!WARNING]
> Be careful to *never* accidentally commit `cosign.key` into your git repo. If this key goes out to the public, the security of your repository is compromised.

Next, you need to add the key to GitHub. This makes use of GitHub's secret signing system.

<details>
    <summary>Using the Github Web Interface (preferred)</summary>

    Go to your repository settings, under `Secrets and Variables` -> `Actions`
    ![image](https://user-images.githubusercontent.com/1264109/216735595-0ecf1b66-b9ee-439e-87d7-c8cc43c2110a.png)
    Add a new secret and name it `SIGNING_SECRET`, then paste the contents of `cosign.key` into the secret and save it. Make sure it's the .key file and not the .pub file. Once done, it should look like this:
    ![image](https://user-images.githubusercontent.com/1264109/216735690-2d19271f-cee2-45ac-a039-23e6a4c16b34.png)
</details>
<details>
<summary>Using the Github CLI</summary>

If you have the `github-cli` installed, run:

```bash
gh secret set SIGNING_SECRET < cosign.key
```
</details>

### Step 2b: Choosing Your Base Image

To choose a base image, simply modify the line in the container file starting with `FROM`. This will be the image your image derives from, and is your starting point for modifications.
For a base image, you can choose any of the Universal Blue images or start from a Fedora Atomic system. Below this paragraph is a dropdown with a non-exhaustive list of potential base images.

<details>
    <summary>Base Images</summary>

    - Bazzite: `ghcr.io/ublue-os/bazzite:stable`
    - Aurora: `ghcr.io/ublue-os/aurora:stable`
    - Bluefin: `ghcr.io/ublue-os/bluefin:stable`
    - Universal Blue Base: `ghcr.io/ublue-os/base-main:latest`
    - Fedora: `quay.io/fedora/fedora-bootc:42`

    You can find more Universal Blue images on the [packages page](https://github.com/orgs/ublue-os/packages).
</details>

If you don't know which image to pick, choosing the one your system is currently on is the best bet for a smooth transition. To find out what image your system currently uses, run the following command:
```bash
sudo bootc status
```
This will show you all the info you need to know about your current image. The image you are currently on is displayed after `Booted image:`. Paste that information after the `FROM` statement in the Containerfile to set it as your base image.

### Step 2c: Changing Names

Change the first line in the [Justfile](./Justfile) to your image's name.

To commit and push all the files changed and added in step 2 into your Github repository:
```bash
git add Containerfile Justfile cosign.pub
git commit -m "Initial Setup"
git push
```
Once pushed, go look at the Actions tab on your Github repository's page.  The green checkmark should be showing on the top commit, which means your new image is ready!

## Step 3: Switch to Your Image

From your bootc system, run the following command substituting in your Github username and image name where noted.
```bash
sudo bootc switch ghcr.io/<username>/<image_name>
```
This should queue your image for the next reboot, which you can do immediately after the command finishes. You have officially set up your custom image! See the following section for an explanation of the important parts of the template for customization.

# Repository Contents

## Containerfile

The [Containerfile](./Containerfile) defines the operations used to customize the selected image.This file is the entrypoint for your image build, and works exactly like a regular podman Containerfile. For reference, please see the [Podman Documentation](https://docs.podman.io/en/latest/Introduction.html).

## build.sh

The [build.sh](./build_files/build.sh) file is called from your Containerfile. It is the best place to install new packages or make any other customization to your system. There are customization examples contained within it for your perusal.

## build.yml

The [build.yml](./.github/workflows/build.yml) Github Actions workflow creates your custom OCI image and publishes it to the Github Container Registry (GHCR). By default, the image name will match the Github repository name. There are several environment variables at the start of the workflow which may be of interest to change.

# Building Disk Images

This template provides an out of the box workflow for creating disk images (ISO, qcow, raw) for your custom OCI image which can be used to directly install onto your machines.

This template provides a way to upload the disk images that is generated from the workflow to a S3 bucket. The disk images will also be available as an artifact from the job, if you wish to use an alternate provider. To upload to S3 we use [rclone](https://rclone.org/) which is able to use [many S3 providers](https://rclone.org/s3/).

## Setting Up ISO Builds

The [build-disk.yml](./.github/workflows/build-disk.yml) Github Actions workflow creates a disk image from your OCI image by utilizing the [bootc-image-builder](https://osbuild.org/docs/bootc/). In order to use this workflow you must complete the following steps:

1. Modify `disk_config/iso.toml` to point to your custom container image before generating an ISO image.
2. If you changed your image name from the default in `build.yml` then in the `build-disk.yml` file edit the `IMAGE_REGISTRY`, `IMAGE_NAME` and `DEFAULT_TAG` environment variables with the correct values. If you did not make changes, skip this step.
3. Finally, if you want to upload your disk images to S3 then you will need to add your S3 configuration to the repository's Action secrets. This can be found by going to your repository settings, under `Secrets and Variables` -> `Actions`. You will need to add the following
  - `S3_PROVIDER` - Must match one of the values from the [supported list](https://rclone.org/s3/)
  - `S3_BUCKET_NAME` - Your unique bucket name
  - `S3_ACCESS_KEY_ID` - It is recommended that you make a separate key just for this workflow
  - `S3_SECRET_ACCESS_KEY` - See above.
  - `S3_REGION` - The region your bucket lives in. If you do not know then set this value to `auto`.
  - `S3_ENDPOINT` - This value will be specific to the bucket as well.

Once the workflow is done, you'll find the disk images either in your S3 bucket or as part of the summary under `Artifacts` after the workflow is completed.

# Artifacthub

This template comes with the necessary tooling to index your image on [artifacthub.io](https://artifacthub.io). Use the `artifacthub-repo.yml` file at the root to verify yourself as the publisher. This is important to you for a few reasons:

- The value of artifacthub is it's one place for people to index their custom images, and since we depend on each other to learn, it helps grow the community. 
- You get to see your pet project listed with the other cool projects in Cloud Native.
- Since the site puts your README front and center, it's a good way to learn how to write a good README, learn some marketing, finding your audience, etc. 

[Discussion Thread](https://universal-blue.discourse.group/t/listing-your-custom-image-on-artifacthub/6446)

# Justfile Documentation

The `Justfile` contains various commands and configurations for building and managing container images and virtual machine images using Podman and other utilities.
To use it, you must have installed [just](https://just.systems/man/en/introduction.html) from your package manager or manually. It is available by default on all Universal Blue images.

## Environment Variables

- `image_name`: The name of the image (default: "image-template").
- `default_tag`: The default tag for the image (default: "latest").
- `bib_image`: The Bootc Image Builder (BIB) image (default: "quay.io/centos-bootc/bootc-image-builder:latest").

## Building The Image

### `just build`

Builds a container image using Podman.

```bash
just build $target_image $tag
```

Arguments:
- `$target_image`: The tag you want to apply to the image (default: `$image_name`).
- `$tag`: The tag for the image (default: `$default_tag`).

## Building and Running Virtual Machines and ISOs

The below commands all build QCOW2 images. To produce or use a different type of image, substitute in the command with that type in the place of `qcow2`. The available types are `qcow2`, `iso`, and `raw`.

### `just build-qcow2`

Builds a QCOW2 virtual machine image.

```bash
just build-qcow2 $target_image $tag
```

### `just rebuild-qcow2`

Rebuilds a QCOW2 virtual machine image.

```bash
just rebuild-vm $target_image $tag
```

### `just run-vm-qcow2`

Runs a virtual machine from a QCOW2 image.

```bash
just run-vm-qcow2 $target_image $tag
```

### `just spawn-vm`

Runs a virtual machine using systemd-vmspawn.

```bash
just spawn-vm rebuild="0" type="qcow2" ram="6G"
```

## File Management

### `just check`

Checks the syntax of all `.just` files and the `Justfile`.

### `just fix`

Fixes the syntax of all `.just` files and the `Justfile`.

### `just clean`

Cleans the repository by removing build artifacts.

### `just lint`

Runs shell check on all Bash scripts.

### `just format`

Runs shfmt on all Bash scripts.

## Community Examples

These are images derived from this template (or similar enough to this template). Reference them when building your image!

- [m2Giles' OS](https://github.com/m2giles/m2os)
- [bOS](https://github.com/bsherman/bos)
- [Homer](https://github.com/bketelsen/homer/)
- [Amy OS](https://github.com/astrovm/amyos)
- [VeneOS](https://github.com/Venefilyn/veneos)

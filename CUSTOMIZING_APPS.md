# Customizing Gamescope Headless Apps

This guide shows how to customize the headless apps that launch with your Gamescope/Steam session.

## Overview

The system uses two files:
1. **Session Config**: `/usr/share/gamescope-session-plus/sessions.d/steam`
   - Defines the `post_gamescope_start()` hook
   - Calls the launcher script

2. **Launcher Script**: `/usr/libexec/startGamescopeApps.sh`
   - Contains the logic for launching individual apps
   - This is where you add/remove apps

## Adding a New Application

### Option 1: Native Application (installed via RPM/DNF)

Edit `/home/runner/work/bazzite-dx/bazzite-dx/system_files/usr/libexec/startGamescopeApps.sh` and add:

```bash
# 5. MyApp - Description of what it does
if command -v myapp &>/dev/null; then
    if launch_app "MyApp" "myapp --start-minimized --background"; then
        ((APPS_LAUNCHED++))
    fi
else
    log "myapp not found, skipping"
fi
```

**Explanation:**
- `command -v myapp` checks if the executable exists
- `launch_app` launches it via xvfb-run (provides virtual X11 display)
- If successful, increments the counter
- If app not installed, skips gracefully with a log message

### Option 2: Flatpak Application

For Flatpak apps, use this pattern:

```bash
# 6. Slack - Team communication
if flatpak list 2>/dev/null | grep -q com.slack.Slack; then
    if launch_app "Slack" "flatpak run com.slack.Slack --startup-mode hidden"; then
        ((APPS_LAUNCHED++))
    fi
else
    log "Slack flatpak not found, skipping"
fi
```

**Explanation:**
- `flatpak list | grep` checks if the flatpak is installed
- Use the full flatpak app ID (e.g., `com.slack.Slack`)
- Add startup flags to minimize/hide the window

### Option 3: AppImage or Custom Script

For AppImages or custom scripts:

```bash
# 7. Custom Tool - My custom automation
CUSTOM_TOOL="${HOME}/.local/bin/my-custom-tool"
if [[ -x "$CUSTOM_TOOL" ]]; then
    if launch_app "CustomTool" "$CUSTOM_TOOL --daemon"; then
        ((APPS_LAUNCHED++))
    fi
else
    log "custom tool not found at $CUSTOM_TOOL, skipping"
fi
```

## Removing an Application

Simply delete or comment out the relevant section. For example, to remove OpenRGB:

```bash
# 4. OpenRGB - RGB lighting control (DISABLED)
# if command -v openrgb &>/dev/null; then
#     if launch_app "OpenRGB" "openrgb --startminimized"; then
#         ((APPS_LAUNCHED++))
#     fi
# else
#     log "openrgb not found, skipping"
# fi
```

## Installing Required Packages

If you want to add an app that's not already installed, add it to `build_files/build.sh`:

```bash
# this installs a package from Fedora repos
dnf5 install -y \
beep \
btfs \
# ... existing packages ...
myapp \            # <-- Add your package here
vlc
```

## Testing Your Changes

After modifying the files:

1. **Test script syntax:**
   ```bash
   bash -n system_files/usr/libexec/startGamescopeApps.sh
   shellcheck system_files/usr/libexec/startGamescopeApps.sh
   ```

2. **Build the image locally (if you have podman):**
   ```bash
   podman build -t test-bazzite-dx .
   ```

3. **Deploy and test:**
   ```bash
   # Commit your changes
   git add .
   git commit -m "Add MyApp to headless apps"
   git push
   
   # Wait for GitHub Actions to build
   # Then deploy the new image
   sudo bootc switch ghcr.io/yourusername/bazzite-dx:latest
   sudo systemctl reboot
   ```

## Advanced: Conditional App Launch

You can add logic to launch apps only under certain conditions:

```bash
# Only launch Discord if we're on a desktop (not a handheld)
if [[ ! -f "/sys/class/dmi/id/product_name" ]] || ! grep -q "Steam Deck\|Ally" /sys/class/dmi/id/product_name; then
    if flatpak list 2>/dev/null | grep -q com.discordapp.Discord; then
        if launch_app "Discord" "flatpak run com.discordapp.Discord --start-minimized"; then
            ((APPS_LAUNCHED++))
        fi
    fi
fi
```

## Environment Variables

Apps launched by the script inherit the Gamescope session environment, including:
- `$DISPLAY` - The Xvfb virtual display (set by xvfb-run)
- `$HOME` - User's home directory
- `$XDG_RUNTIME_DIR` - Runtime directory for the user
- `$GAMESCOPE_WAYLAND_DISPLAY` - Gamescope's Wayland display (if needed)

## Troubleshooting

### App doesn't start
1. Check logs:
   ```bash
   # From within Gamescope session
   journalctl --user -u gamescope-session-plus@steam.service | grep gamescopeApps
   ```

2. Verify app is installed:
   ```bash
   command -v myapp
   # or for flatpak:
   flatpak list | grep myapp
   ```

3. Test app manually with xvfb-run:
   ```bash
   xvfb-run -a -s "-screen 0 1024x768x24" myapp --args
   ```

### App starts but crashes
- Check if app needs specific environment variables
- Some apps don't work well headless (need real display)
- Try launching without xvfb-run if app is CLI-only

### Multiple instances launching
- The PID file prevents this by default
- If you see duplicates, check that `$XDG_RUNTIME_DIR` is set correctly

## Examples of Good Candidates for Headless Apps

**✅ Good:**
- Cloud sync clients (Dropbox, MEGAsync, pCloud, Nextcloud)
- Chat/communication (Discord, Slack, Element)
- Background utilities (OpenRGB, CoolerControl, liquidctl)
- System monitors (GameMode, MangoHUD configurators)
- Media servers (Plex, Jellyfin tray apps)

**❌ Not Recommended:**
- Apps that need frequent user interaction
- Apps with no minimize/background mode
- Resource-heavy apps that affect gaming performance
- Apps that require GPU access (will conflict with Gamescope)

## Contributing Your Customizations

If you add a useful app that others might want, consider:
1. Opening an issue on the repository
2. Submitting a pull request with your changes
3. Documenting why the app is useful for gaming setups

## Related Files

- Main implementation: `system_files/usr/libexec/startGamescopeApps.sh`
- Session hook: `system_files/usr/share/gamescope-session-plus/sessions.d/steam`
- Package installation: `build_files/build.sh`
- Container build: `Containerfile`

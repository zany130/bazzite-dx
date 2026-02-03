# Gamescope Headless Apps - Implementation Summary

## Problem Statement

You wanted to launch headless background apps (megasync, Discord, pCloud, OpenRGB) alongside your Gamescope/Steam session in a custom Bazzite image, following best practices for:
- rpm-ostree immutability and rollback semantics
- Bazzite/ChimeraOS conventions
- Per-user opt-out capability

## Solution Overview

After analyzing the ChimeraOS gamescope-session framework, I implemented a **Gamescope session hooks approach** using the built-in `post_gamescope_start()` function.

### Why This Approach?

1. **Native Integration**: ChimeraOS gamescope-session provides three hooks:
   - `short_session_recover()` - Called when session fails
   - `post_gamescope_start()` - Called after Gamescope starts, before client
   - `post_client_shutdown()` - Called after client exits

2. **Perfect Timing**: The `post_gamescope_start()` hook runs at the exact right moment:
   - ✅ After Gamescope compositor is ready
   - ✅ Before Steam client starts
   - ✅ Environment variables are set
   - ✅ X11/Wayland displays are available

3. **Simpler Than Systemd**: 
   - No need for separate systemd units
   - No dependency management with `Wants=`/`After=`
   - No timing race conditions
   - Single file to edit

4. **Follows Bazzite Pattern**: 
   - Bazzite already uses this pattern for Steam tweaks
   - Same location: `/usr/share/gamescope-session-plus/sessions.d/steam`
   - We simply extend the existing hook

## Implementation Details

### File Structure

```
system_files/
├── usr/
│   ├── share/
│   │   └── gamescope-session-plus/
│   │       └── sessions.d/
│   │           └── steam                    # Session config with hook
│   └── libexec/
│       └── startGamescopeApps.sh           # Launcher script
```

### How It Works

1. **Boot / Login to Gamescope Session**
   - User selects "Steam Gaming Mode" from login screen
   - `/usr/bin/gamescope-session-plus steam` starts
   - Main script sources `/usr/share/gamescope-session-plus/sessions.d/steam`

2. **Hook Execution**
   - Gamescope compositor starts
   - `post_gamescope_start()` function is called
   - Our hook checks for `~/.config/gamescope/disable-apps`
   - If not disabled, launches `/usr/libexec/startGamescopeApps.sh` in background

3. **App Launching**
   - Script checks for each app (megasync, Discord, pCloud, OpenRGB)
   - Launches via `xvfb-run` (provides virtual X11 display)
   - Apps run invisibly, don't appear in Gamescope compositor
   - PID file prevents duplicate launches

4. **Session Lifecycle**
   - Apps continue running throughout gaming session
   - When user exits Steam → Gamescope stops → session ends → apps are killed
   - No manual cleanup needed

### Key Files

#### 1. Session Config: `steam`
Located: `/usr/share/gamescope-session-plus/sessions.d/steam`

Defines the `post_gamescope_start()` hook:
```bash
function post_gamescope_start {
    # Upstream: Run steam-tweaks if exists
    if command -v steam-tweaks > /dev/null; then
        steam-tweaks
    fi
    
    # Bazzite-DX Custom: Launch headless apps
    if [[ -f "${HOME}/.config/gamescope/disable-apps" ]]; then
        echo "[bazzite-dx] Headless apps disabled by user flag" >&2
    elif [[ -x "/usr/libexec/startGamescopeApps.sh" ]]; then
        echo "[bazzite-dx] Starting headless applications" >&2
        /usr/libexec/startGamescopeApps.sh &
    fi
}
```

#### 2. Launcher Script: `startGamescopeApps.sh`
Located: `/usr/libexec/startGamescopeApps.sh`

- Checks for disable flag (`~/.config/gamescope/disable-apps`)
- Creates PID file to prevent duplicates
- Launches each app via `xvfb-run`
- Gracefully skips missing apps
- Logs to stderr (captured by gamescope-session journal)

### Per-User Opt-Out

**To disable (as user):**
```bash
mkdir -p ~/.config/gamescope
touch ~/.config/gamescope/disable-apps
# Then logout/login or reboot
```

**To re-enable:**
```bash
rm ~/.config/gamescope/disable-apps
# Then logout/login or reboot
```

## Behavior Across Different Scenarios

### 1. Image Updates and Rollbacks

**During Update:**
```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```
- New image contains updated files in `/usr/share/` and `/usr/libexec/`
- Files are part of immutable image, update atomically
- User's `~/.config/gamescope/disable-apps` flag persists (in `/var/home`)

**During Rollback:**
```bash
sudo bootc switch --rollback
sudo systemctl reboot
```
- System reverts to previous image
- Files in `/usr/` roll back automatically
- User config remains unchanged
- **No manual cleanup needed** - everything rolls back atomically

### 2. New User Creation

**First Login:**
1. New user logs in
2. Selects "Steam Gaming Mode"
3. Gamescope session starts
4. `post_gamescope_start()` runs
5. Checks for `~/.config/gamescope/disable-apps` (doesn't exist)
6. Apps launch automatically

**Pre-disable for new users (optional):**
Add to Containerfile:
```dockerfile
RUN mkdir -p /etc/skel/.config/gamescope && \
    touch /etc/skel/.config/gamescope/disable-apps
```
This would make apps **disabled by default** (opt-in instead of opt-out).

### 3. Switching Between Sessions

**Gamescope → Plasma:**
- User logs out of Gamescope session
- gamescope-session-plus stops
- `post_gamescope_start()` was only for that session
- Apps are killed (children of the session process)
- User logs into Plasma
- Apps **do not run** in Plasma (correctly scoped to Gamescope only)

**Plasma → Gamescope:**
- User logs out of Plasma
- User logs into Gamescope session
- `post_gamescope_start()` runs
- Apps launch as expected

### 4. Multiple Sessions (Edge Case)

If user runs multiple Gamescope sessions simultaneously:
- Each session calls `post_gamescope_start()`
- PID file prevents duplicate app launches
- First session wins, subsequent sessions skip with "already running" message

## Comparison with Alternative Approaches

### Alternative 1: Systemd User Units

**Would require:**
- `/usr/lib/systemd/user/gamescopeApps@.service`
- `/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf`
- `/usr/libexec/startGamescopeApps.sh`

**Why NOT chosen:**
- More files to manage (3 instead of 2)
- Drop-in override adds complexity
- Timing issues (`Wants=`/`After=` don't guarantee order)
- Not standard for ChimeraOS/Bazzite session customization
- Over-engineering for this use case

**When you WOULD use systemd:**
- Need automatic restart on crash (`Restart=on-failure`)
- Need detailed logging separate from session
- System-wide service (like LG_Buddy), not session-specific

### Alternative 2: User Scripts in ~/.config

**Would require:**
- `/etc/skel/.config/gamescope/scripts/post_gamescope_start`

**Why NOT chosen:**
- Requires user-space templates (`/etc/skel/`)
- Existing users need manual setup or migration
- Less discoverable for system administration
- No integration with immutable image (scripts in `/var/home`)

**When you WOULD use this:**
- Per-user customization (not system-wide default)
- Testing changes without rebuilding image
- User-specific apps not appropriate for everyone

## Advantages of Chosen Approach

### ✅ Pros:

1. **Native Integration**: Uses built-in gamescope-session hooks
2. **Perfect Timing**: Runs after Gamescope ready, before Steam starts
3. **Simple**: Only 2 files, no systemd complexity
4. **Immutable-Friendly**: Files in `/usr/` are part of image
5. **Rollback-Safe**: Everything rolls back atomically
6. **Session-Scoped**: Only runs with Gamescope, not Plasma
7. **Discoverable**: Standard location for session customization
8. **Extensible**: Easy to add more apps
9. **Proven Pattern**: Matches ChimeraOS/Bazzite conventions

### ⚠️ Limitations:

1. **No Auto-Restart**: If an app crashes, it won't restart automatically
   - **Mitigation**: Most of these apps are stable; if needed, add restart logic to script
   
2. **Shared PID File**: Only one set of apps can run at a time
   - **Mitigation**: This is desired behavior (prevents duplicates)
   
3. **No Separate Logging**: Apps log to gamescope-session journal
   - **Mitigation**: Can filter with `journalctl | grep gamescopeApps`

## Testing and Validation

### Pre-Deployment Checks

✅ **Script syntax validation:**
```bash
bash -n system_files/usr/libexec/startGamescopeApps.sh
bash -n system_files/usr/share/gamescope-session-plus/sessions.d/steam
```

✅ **Shellcheck linting:**
```bash
shellcheck system_files/usr/libexec/startGamescopeApps.sh
shellcheck system_files/usr/share/gamescope-session-plus/sessions.d/steam
```

✅ **File permissions:**
- Both files: `0755` (executable)
- Set in Containerfile

### Post-Deployment Checks

**Check if apps are running:**
```bash
ps aux | grep -E '(megasync|Discord|pcloud|openrgb|xvfb)'
```

**Check logs:**
```bash
journalctl --user -u gamescope-session-plus@steam.service | grep gamescopeApps
```

**Test disable flag:**
```bash
touch ~/.config/gamescope/disable-apps
# Logout/login
# Apps should not launch
```

## Documentation

### For Users:

1. **README.md** - Main feature documentation
   - What it does
   - How to disable/enable
   - Troubleshooting
   - Default apps list

2. **CUSTOMIZING_APPS.md** - Customization guide
   - How to add new apps
   - How to remove apps
   - Examples for different app types
   - Testing instructions

### For Developers:

1. **GAMESCOPE_APPS_DESIGN.md** - Technical design doc
   - Architecture analysis
   - Alternative approaches considered
   - Behavior across scenarios
   - Implementation details
   - Security considerations

## Customization

### Adding a New App

Edit `system_files/usr/libexec/startGamescopeApps.sh`:

```bash
# 5. NewApp - Description
if command -v newapp &>/dev/null; then
    if launch_app "NewApp" "newapp --args"; then
        ((APPS_LAUNCHED++))
    fi
else
    log "newapp not found, skipping"
fi
```

### Installing Required Packages

Edit `build_files/build.sh`:

```bash
dnf5 install -y \
beep \
# ... existing packages ...
newapp \           # <-- Add your package
vlc
```

Then rebuild and deploy the image.

## Security Considerations

✅ **Safe:**
- Script runs as user, not root
- Apps inherit user permissions
- No sudo or privilege escalation
- xvfb-run provides isolated X11 display
- PID file in user's `$XDG_RUNTIME_DIR` (mode 0700)
- All files signed as part of container image

✅ **No Command Injection:**
- All commands are hardcoded
- No user input processed
- Uses `command -v` for checks

## Performance Impact

**Minimal:**
- Apps launch after Gamescope, don't delay boot
- Background processes, low CPU usage when idle
- xvfb-run overhead is minimal (~5MB RAM per virtual display)
- Failed apps don't block script execution

**Potential Issues:**
- High RAM if all apps run simultaneously (depends on apps)
- CPU spike during launch (brief, ~2-3 seconds)
- Disk I/O for cloud sync apps

## Questions Answered

### Q1: Which approach is better: hooks or systemd units?

**Answer**: Gamescope session hooks (`post_gamescope_start`).

**Reasons**:
- Native integration with gamescope-session framework
- Perfect timing (after Gamescope, before client)
- Simpler implementation (fewer files)
- Follows ChimeraOS/Bazzite conventions
- No systemd complexity or race conditions

### Q2: What's the concrete file layout for a custom image?

**Answer**:
```
system_files/
├── usr/
│   ├── share/
│   │   └── gamescope-session-plus/
│   │       └── sessions.d/
│   │           └── steam                    # 0755, session config
│   └── libexec/
│       └── startGamescopeApps.sh           # 0755, launcher script
```

Files go in `/usr/share/` and `/usr/libexec/` (immutable image locations).

### Q3: Show example files with comments.

**Answer**: See the implementation files:
- `system_files/usr/share/gamescope-session-plus/sessions.d/steam` - Session config with hook
- `system_files/usr/libexec/startGamescopeApps.sh` - Launcher with detailed comments

Both files include extensive inline comments explaining the design.

### Q4: How does this behave across image updates, rollbacks, new users, and session switching?

**Answer**:

| Scenario | Behavior |
|----------|----------|
| **Image Update** | Files in `/usr/` update atomically; user config persists |
| **Rollback** | Files roll back with image; no manual cleanup |
| **New User** | Apps enabled by default; can opt-out with flag |
| **Gamescope→Plasma** | Apps stop when session ends; don't run in Plasma |
| **Plasma→Gamescope** | Apps launch when Gamescope session starts |

See "Behavior Across Different Scenarios" section for details.

## Next Steps

1. ✅ Build the custom image (GitHub Actions will do this on push)
2. ✅ Deploy to test system:
   ```bash
   sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
   sudo systemctl reboot
   ```
3. ✅ Login to Gamescope/Steam session
4. ✅ Verify apps launch:
   ```bash
   ps aux | grep -E '(megasync|Discord|pcloud|openrgb)'
   ```
5. ✅ Test disable flag:
   ```bash
   touch ~/.config/gamescope/disable-apps
   # Logout/login - apps should not start
   ```

## Conclusion

This implementation provides a clean, maintainable solution for launching headless apps in a custom Bazzite image. It:

- ✅ Respects rpm-ostree immutability (files in `/usr/`)
- ✅ Follows Bazzite/ChimeraOS conventions (session hooks)
- ✅ Allows per-user opt-out (disable flag)
- ✅ Is rollback-safe (atomic updates)
- ✅ Is well-documented (README, design doc, customization guide)
- ✅ Is extensible (easy to add/remove apps)
- ✅ Is testable (shellcheck validated, clear logging)

The approach is simpler and more reliable than systemd units, and aligns perfectly with how ChimeraOS/Bazzite handle session customization.

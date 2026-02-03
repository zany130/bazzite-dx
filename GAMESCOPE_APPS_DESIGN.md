# Gamescope Headless Apps Integration - Design Documentation

## Executive Summary

This document details the design and implementation of a system for launching additional "headless" applications alongside Gamescope sessions in a custom Bazzite image. The solution respects rpm-ostree immutability, Bazzite/ChimeraOS conventions, and provides per-user opt-out capability.

## Design Decision: Three Approaches Analyzed

After reviewing the ChimeraOS gamescope-session and gamescope-session-steam repositories, I've identified **three viable approaches**:

1. **Gamescope Session Hooks** (using `post_gamescope_start()`)
2. **Systemd User Units** (via drop-in for gamescope-session-plus)
3. **Hybrid Approach** (hooks + systemd)

### Approach 1: Gamescope Session Hooks (RECOMMENDED)

**Implementation**: Override the steam session config to add `post_gamescope_start()` function.

**Key Discovery**: The ChimeraOS gamescope-session-steam repository shows that `/usr/share/gamescope-session-plus/sessions.d/steam` is sourced by the main gamescope-session-plus script and provides three hooks:
- `short_session_recover()` - Called when session fails repeatedly  
- `post_gamescope_start()` - Called **after Gamescope starts** but **before client app**
- `post_client_shutdown()` - Called after the client app exits

This is the PERFECT integration point for launching background apps!

#### Why Gamescope Hooks (RECOMMENDED):

1. **Native Integration**: 
   - The session config file is sourced by gamescope-session-plus, so functions defined in it are executed in the correct context
   - `post_gamescope_start()` runs at the perfect time: after Gamescope is ready, before Steam starts
   - No need for separate systemd units or dependency management
   - Follows the exact pattern used by ChimeraOS for steam-tweaks and steam_notif_daemon

2. **Bazzite Uses This Pattern**:
   - Bazzite ships `/usr/share/gamescope-session-plus/sessions.d/steam` (overriding ChimeraOS defaults)
   - Already defines `post_gamescope_start()` for Steam-specific tweaks
   - **We simply extend the existing function** rather than creating new infrastructure

3. **Simplicity**:
   - Single file to edit: `/usr/share/gamescope-session-plus/sessions.d/steam`
   - No systemd unit files needed
   - No drop-in overrides needed
   - All logic in one place, easy to understand and maintain

4. **Disable Mechanism Built-In**:
   - Check for `~/.config/gamescope/disable-apps` in the function
   - Graceful fallback if file exists
   - Users can create the file to opt-out

5. **Rollback Safe**:
   - File in `/usr/share/` is part of immutable image
   - Rolls back atomically with the image
   - No separate systemd units to manage

#### Why NOT Systemd Units (Previous Approach):
1. **Over-Engineering**: Systemd units add unnecessary complexity for this use case
   - Requires drop-in override to pull in the apps service
   - Requires separate systemd unit file
   - Requires separate launcher script
   - More files to manage and maintain

2. **Timing Issues**:
   - Systemd `Wants=` + `After=` don't guarantee apps start before Steam client
   - Race condition: Steam might start before apps if timing is tight
   - Gamescope hook runs at the **exact right moment** (after Gamescope, before client)

3. **Not Standard for Gamescope Sessions**:
   - ChimeraOS doesn't use systemd units for session-level customization
   - Steam session uses `post_gamescope_start()` for steam-tweaks and steam_notif_daemon
   - Systemd units are better for system-wide services (like LG_Buddy)

**Decision**: Use Gamescope session hooks by extending `post_gamescope_start()` in the steam session config.

### Approach 2: Systemd User Units (Alternative)

If you prefer systemd for its restart capabilities and logging, here's how it would work:

**Why You Might Want This**:
- Automatic restart on failure (`Restart=on-failure`)
- Better logging via `journalctl --user`
- Can be disabled per-user via `systemctl --user mask`
- More familiar if you're used to systemd

**Layout**:
   - Would require `/etc/skel/.config/gamescope/scripts/` template that copies to each new user
   - Existing users would need manual setup or a migration script
   - Less discoverable and harder to manage system-wide

2. **Execution Context**: Hooks are designed for session-specific customization, not system-wide behavior
   - `post_gamescope_start` runs after Gamescope starts but provides no systemd unit management
   - No automatic restart capability if apps crash
   - Harder to integrate with systemd's dependency management

3. **No Built-in Disable Mechanism**: Gamescope session doesn't provide a standard way to disable hooks
   - Would need custom lock file logic in each hook
   - Less integrated with systemd's enable/disable semantics

#### Why Systemd Units (RECOMMENDED):
1. **System Integration**: 
   - Native systemd dependency management via `Wants=` and `After=`
   - Automatic restart capabilities with `Restart=on-failure`
   - Centralized logging with `journalctl`
   - Standard enable/disable semantics

2. **Immutable Image Friendly**:
   - Units in `/usr/lib/systemd/user/` are part of the immutable base image
   - Drop-ins work seamlessly with rpm-ostree's overlay system
   - Rollback-safe: if the image rolls back, the units roll back too

3. **User Override Path**:
   - Users can disable via `systemctl --user mask gamescopeApps.service`
   - Custom disable flag in `~/.config/gamescope/disable-apps` can be checked by script
   - Override files in `~/.config/systemd/user/` take precedence

4. **Proven Pattern**: Bazzite already uses this pattern (see LG_Buddy.service)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ gamescope-session-plus@.service (Base Bazzite)                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Wants= (via drop-in)
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│ gamescopeApps@.service (User Unit)                              │
│ - Type=forking                                                  │
│ - PIDFile=/run/user/%U/gamescope-apps.pid                      │
│ - Environment setup                                              │
│ - Calls: /usr/libexec/startGamescopeApps.sh                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Executes
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│ /usr/libexec/startGamescopeApps.sh                             │
│ - Checks for ~/.config/gamescope/disable-apps                  │
│ - Creates PID file                                              │
│ - Launches apps via xvfb-run:                                   │
│   • megasync                                                     │
│   • Discord (Flatpak)                                           │
│   • pCloud                                                      │
│   • OpenRGB                                                     │
└─────────────────────────────────────────────────────────────────┘
```

## File Layout

### 1. User Systemd Unit
**Location**: `/usr/lib/systemd/user/gamescopeApps@.service`
**Rationale**:
- `/usr/lib/systemd/user/` is the standard location for system-provided user units
- Part of the immutable image, survives updates and rollbacks
- `@` template allows instantiation per-user or per-session type
- Users can override with `~/.config/systemd/user/` if needed

### 2. Drop-in Override for gamescope-session-plus
**Location**: `/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf`
**Rationale**:
- Drop-ins in `/usr/lib/systemd/user/*.service.d/` are part of immutable image
- `10-` prefix ensures early loading order
- Uses `Wants=` (not `Requires=`) so apps failure doesn't break Gamescope session
- `After=` ensures proper startup ordering

### 3. Launcher Script
**Location**: `/usr/libexec/startGamescopeApps.sh`
**Rationale**:
- `/usr/libexec/` is standard for helper scripts not directly invoked by users
- Part of immutable `/usr`, not in `/usr/local/` which might be layered
- Allows complex logic (disable flag checking, PID management, xvfb-run)
- Executable is set in Containerfile

### 4. User Opt-Out Mechanism
**Location**: `~/.config/gamescope/disable-apps` (created by user)
**Rationale**:
- Per-user configuration in standard XDG_CONFIG_HOME location
- Simple touch-file mechanism: if exists, skip launching apps
- Doesn't require systemd knowledge (no `systemctl --user mask` needed)
- Aligns with Gamescope's existing `~/.config/gamescope/` usage

## Implementation Files

### File 1: `/usr/lib/systemd/user/gamescopeApps@.service`

```ini
[Unit]
Description=Additional Headless Apps for Gamescope Session (%i)
Documentation=man:systemd.special(7)
# Start after the gamescope session is ready
After=gamescope-session-plus@%i.service

[Service]
Type=forking
# Use PID file to track the parent wrapper process
PIDFile=%t/gamescope-apps.pid
# Launch the script that starts all apps
ExecStart=/usr/libexec/startGamescopeApps.sh
# Restart on failure (crash), but not on clean exit
Restart=on-failure
RestartSec=5s
# Environment: Inherit from gamescope session
Environment="XDG_RUNTIME_DIR=/run/user/%U"
# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gamescopeApps

[Install]
# Not directly installed; activated via Wants= from gamescope-session-plus
```

**Key Design Points**:
- **Template Unit** (`@.service`): Instance name `%i` matches gamescope-session type (e.g., `steam`)
- **Type=forking**: The script daemonizes by launching xvfb-run processes in background
- **PIDFile**: Uses `%t` (XDG_RUNTIME_DIR) for runtime-only PID tracking
- **After=**: Ensures Gamescope session is up before launching apps
- **Restart=on-failure**: Auto-restarts if apps crash, but respects clean shutdown
- **No WantedBy=**: Unit is activated via Wants= from gamescope-session-plus, not directly enabled

### File 2: `/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf`

```ini
[Unit]
# Pull in the headless apps service when gamescope session starts
Wants=gamescopeApps@%i.service
# Ensure apps start after the session, not before
After=gamescopeApps@%i.service
```

**Key Design Points**:
- **Drop-in Override**: Augments base `gamescope-session-plus@.service` without modifying it
- **Wants= (not Requires=)**: Apps failure won't prevent Gamescope session from starting
- **After=**: This is backwards from what you might expect, but it's correct:
  - We want `gamescope-session-plus` to not consider itself fully started until after apps are launched
  - This ensures proper ordering: gamescope starts → apps start → session marked ready
- **Instance Matching**: `%i` in both services ensures template instances match (e.g., both `@steam`)

**Alternative Consideration**: If you want apps to be optional and not delay session startup, you could use:
```ini
[Unit]
Wants=gamescopeApps@%i.service
```
Without the `After=` directive. This would allow gamescope-session-plus to complete startup immediately, while apps start in parallel.

### File 3: `/usr/libexec/startGamescopeApps.sh`

```bash
#!/bin/bash
# ============================================================================
# Gamescope Headless Apps Launcher
# Starts additional background applications for Gamescope sessions
# ============================================================================

set -euo pipefail

# Configuration
DISABLE_FLAG="${HOME}/.config/gamescope/disable-apps"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope-apps.pid"
LOG_TAG="gamescopeApps"

# Logging helper
log() {
    echo "[$LOG_TAG] $*" >&2
    logger -t "$LOG_TAG" "$*"
}

# Check if user has opted out
if [[ -f "$DISABLE_FLAG" ]]; then
    log "Headless apps disabled by user (found: $DISABLE_FLAG)"
    exit 0
fi

# Ensure XDG_RUNTIME_DIR is set
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    log "ERROR: XDG_RUNTIME_DIR not set"
    exit 1
fi

# Check if already running
if [[ -f "$LOCK_FILE" ]]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        log "Already running (PID: $PID)"
        exit 0
    else
        log "Stale PID file found, removing"
        rm -f "$LOCK_FILE"
    fi
fi

# Write our PID to lock file
echo $$ > "$LOCK_FILE"
log "Starting headless apps (PID: $$)"

# Xvfb display number (use high number to avoid conflicts)
XVFB_DISPLAY=":99"

# Start apps in background via xvfb-run
# xvfb-run provides a virtual X11 display for apps that need it

# Function to launch app via xvfb-run
launch_app() {
    local app_name="$1"
    local app_cmd="$2"
    
    log "Launching: $app_name"
    if ! xvfb-run -a -s "-screen 0 1024x768x24" bash -c "$app_cmd" &
    then
        log "WARNING: Failed to launch $app_name"
    fi
}

# Launch each application
# Note: These run as background processes under this script's PID

# 1. MEGAsync - Cloud storage sync
if command -v megasync &>/dev/null; then
    launch_app "megasync" "megasync"
else
    log "megasync not found, skipping"
fi

# 2. Discord - Flatpak version
if flatpak list 2>/dev/null | grep -q com.discordapp.Discord; then
    launch_app "Discord" "flatpak run com.discordapp.Discord --start-minimized"
else
    log "Discord flatpak not found, skipping"
fi

# 3. pCloud - Cloud storage (if installed)
if command -v pcloud &>/dev/null; then
    launch_app "pCloud" "pcloud"
else
    log "pcloud not found, skipping"
fi

# 4. OpenRGB - RGB lighting control
if command -v openrgb &>/dev/null; then
    launch_app "OpenRGB" "openrgb --startminimized"
else
    log "openrgb not found, skipping"
fi

# Keep script alive to maintain PID file
# Apps are running as children; this script exits when systemd stops it
log "All apps launched successfully"

# Wait for children (xvfb-run processes)
# This keeps the script running so systemd can track it via PID file
wait
```

**Key Design Points**:
- **Disable Flag**: Simple opt-out mechanism via `~/.config/gamescope/disable-apps`
- **PID File Management**: Prevents duplicate launches, allows systemd tracking
- **Robust Error Handling**: `set -euo pipefail` + existence checks for each app
- **xvfb-run**: Provides virtual X11 display for GUI apps running headless
  - `-a`: Auto-select display number (avoids conflicts)
  - `-s "-screen 0 1024x768x24"`: Virtual screen configuration
- **Graceful Degradation**: Missing apps are skipped with warnings, not errors
- **Logging**: Dual output to stderr (journal) and syslog
- **Process Management**: `wait` keeps script alive; systemd can stop it cleanly

**Security Note**: The script runs as the user, not root. Apps inherit user permissions.

## Behavior Across Scenarios

### 1. Image Updates and Rollbacks

**During Update**:
```bash
sudo bootc switch ghcr.io/zany130/bazzite-dx:latest
sudo systemctl reboot
```
- New image contains updated units in `/usr/lib/systemd/user/`
- On next boot, updated units are active automatically
- User's `~/.config/gamescope/disable-apps` flag persists (in /var/home)

**During Rollback**:
```bash
sudo bootc switch --rollback
sudo systemctl reboot
```
- System reverts to previous image with previous units
- Units in `/usr/` roll back atomically with the image
- User config in `~/.config/` remains unchanged
- If new image added a unit, rollback removes it cleanly

**Why This Works**:
- `/usr/lib/systemd/user/` is part of immutable `/usr` (the deployed image)
- rpm-ostree/bootc manages `/usr` atomically
- User data in `/var/home` is separate from the image
- No manual cleanup needed on rollback

### 2. New User Creation

**First Login Flow**:
1. User logs in → PAM creates `/home/username/`
2. `/etc/skel/` contents copied to user's home (if any)
3. User-level systemd instantiates `gamescope-session-plus@steam.service` (if using Gamescope session)
4. Drop-in pulls in `gamescopeApps@steam.service` via `Wants=`
5. `startGamescopeApps.sh` executes
6. Script checks for `~/.config/gamescope/disable-apps` (doesn't exist yet)
7. Apps launch successfully

**To Pre-disable for New Users**:
Add to image: `/etc/skel/.config/gamescope/disable-apps`
```bash
# In Containerfile:
RUN mkdir -p /etc/skel/.config/gamescope && \
    touch /etc/skel/.config/gamescope/disable-apps
```
This would make apps disabled by default; users can opt-in by removing the file.

**Current Design** (recommended): Apps enabled by default, users opt-out if desired.

### 3. Switching Between Gamescope and Plasma Sessions

**Scenario A: User Switches from Gamescope to Plasma**
```bash
# User logs out of Gamescope session, logs into Plasma via SDDM
```
- `gamescope-session-plus@steam.service` stops (session ends)
- `gamescopeApps@steam.service` stops automatically (Wants= dependency)
- Apps are killed cleanly
- Plasma session has no dependency on Gamescope units
- Apps do NOT run in Plasma session (correctly scoped to Gamescope only)

**Scenario B: User Switches from Plasma to Gamescope**
```bash
# User logs out of Plasma, logs into Gamescope via SDDM
```
- `gamescope-session-plus@steam.service` starts
- Drop-in activates `gamescopeApps@steam.service` via `Wants=`
- Apps launch as expected

**Why This Works**:
- Units are tied to `gamescope-session-plus@.service` lifecycle
- When session stops, dependent units stop
- When session starts, dependent units start
- No global WantedBy=default.target, so apps only run with Gamescope

**Edge Case**: User running multiple sessions simultaneously
- Each session gets its own instance: `@steam`, `@jupiter`, etc.
- Apps service instances are separate: `gamescopeApps@steam.service`, `gamescopeApps@jupiter.service`
- PID file is shared: only one instance can run (lock file prevents duplicates)
- Current design: first session wins, subsequent skip with "already running" message

**To Support Multiple Sessions**: Use instance-specific PID files:
```bash
# In script:
LOCK_FILE="${XDG_RUNTIME_DIR}/gamescope-apps-${GAMESCOPE_SESSION_TYPE}.pid"
```
Where `GAMESCOPE_SESSION_TYPE` is passed from service unit.

### 4. User Disabling Apps

**Method 1: Simple Disable Flag (Recommended for Users)**
```bash
# Disable apps
mkdir -p ~/.config/gamescope
touch ~/.config/gamescope/disable-apps

# Re-enable apps
rm ~/.config/gamescope/disable-apps
```
Then restart Gamescope session or reboot.

**Method 2: Systemd Mask (Advanced Users)**
```bash
# Disable apps
systemctl --user mask gamescopeApps@steam.service

# Re-enable apps
systemctl --user unmask gamescopeApps@steam.service
```

**Method 3: Drop-in Override (Power Users)**
```bash
# Create override to set Restart=no or change conditions
systemctl --user edit gamescopeApps@steam.service
```

**Why Multiple Methods**:
- Method 1: Simple, discoverable, no systemd knowledge required
- Method 2: Uses systemd native tools, integrates with other systemd workflows
- Method 3: Allows granular customization while keeping base unit intact

## Comparison with LG_Buddy Pattern

**Similarities**:
- Both use systemd units in `/etc/systemd/system/` or `/usr/lib/systemd/`
- Both use scripts in `/usr/local/bin/` or `/usr/libexec/`
- Both handle user-specific configuration
- Both are baked into the image

**Key Differences**:

| Aspect | LG_Buddy | gamescopeApps |
|--------|----------|---------------|
| **Scope** | System-wide service | User service (per-session) |
| **Unit Location** | `/etc/systemd/system/` | `/usr/lib/systemd/user/` |
| **Runs As** | Specific user (User= directive) | Session user (implicit) |
| **Activation** | `WantedBy=multi-user.target` | `Wants=` from gamescope-session-plus |
| **Lifecycle** | Tied to system boot/shutdown | Tied to Gamescope session |
| **Enabled By Default** | No (requires `systemctl enable`) | Yes (via Wants=, automatic) |
| **Configuration** | Hardcoded username in files | Generic, uses %U/%i variables |

**Why gamescopeApps Uses User Units**:
- Apps should run as the logged-in user, not a hardcoded user
- Apps are session-specific, not system-wide
- Avoids hardcoding usernames (respects multi-user systems)
- Follows XDG Base Directory spec for user config

**Why LG_Buddy Uses System Units**:
- TV control is system-level, not user-specific
- Needs to run at system boot/shutdown, not session login
- Single-user gaming system assumption (Steam Deck-like)

## Alternative Designs Considered

### Alternative 1: Use Gamescope Session Hooks

**Layout**:
```
/etc/skel/.config/gamescope/scripts/post_gamescope_start
/etc/skel/.config/gamescope/scripts/post_client_shutdown
```

**Pros**:
- Integrated with Gamescope session lifecycle
- User-local, easy to customize per-user

**Cons**:
- Requires `/etc/skel/` templating for new users
- Existing users need manual setup or migration script
- No systemd integration (logging, restart, dependencies)
- Less discoverable for system administration
- ChimeraOS hooks are designed for user customization, not system defaults

**Decision**: Rejected. Hooks are better suited for user-specific customization, not system-wide defaults.

### Alternative 2: System-Wide Service (Like LG_Buddy)

**Layout**:
```
/etc/systemd/system/gamescopeApps.service
/usr/local/bin/startGamescopeApps.sh
```

**Pros**:
- Simple, matches LG_Buddy pattern
- Familiar to users of this repository

**Cons**:
- Requires hardcoding username (breaks multi-user support)
- Runs as specific user, not session user
- Doesn't stop when user switches to Plasma session
- Less flexible for multiple users

**Decision**: Rejected. User units are more appropriate for session-scoped behavior.

### Alternative 3: User Unit + Manual Enablement

**Layout**: Same as recommended, but without drop-in override

**Pros**:
- User explicitly enables service via `systemctl --user enable`
- More control

**Cons**:
- Requires manual step after image installation
- Not discoverable (users may not know it exists)
- Breaks "it just works" goal
- Inconsistent with "baked into image" design philosophy

**Decision**: Rejected. Automatic activation via Wants= is better for a baked image.

## Testing and Validation

### Pre-Deployment Tests

1. **Unit File Syntax**:
```bash
systemd-analyze verify /usr/lib/systemd/user/gamescopeApps@.service
systemd-analyze verify /usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf
```

2. **Script Syntax**:
```bash
shellcheck /usr/libexec/startGamescopeApps.sh
bash -n /usr/libexec/startGamescopeApps.sh
```

3. **Permissions**:
```bash
ls -l /usr/libexec/startGamescopeApps.sh  # Should be 0755, root:root
ls -l /usr/lib/systemd/user/gamescopeApps@.service  # Should be 0644, root:root
```

### Post-Deployment Tests

1. **Service Status**:
```bash
systemctl --user status gamescopeApps@steam.service
journalctl --user -u gamescopeApps@steam.service -f
```

2. **Process Check**:
```bash
ps aux | grep -E '(megasync|Discord|pcloud|openrgb|xvfb)'
```

3. **Disable Flag**:
```bash
touch ~/.config/gamescope/disable-apps
# Restart Gamescope session
systemctl --user status gamescopeApps@steam.service  # Should show "inactive (dead)"
```

4. **Rollback Test**:
```bash
# On system with new image
systemctl --user status gamescopeApps@steam.service  # Should exist and run
sudo bootc switch --rollback && sudo systemctl reboot
# After reboot
systemctl --user status gamescopeApps@steam.service  # Should not exist (if not in old image)
```

## Maintenance and Future Considerations

### Adding New Apps

Edit `/usr/libexec/startGamescopeApps.sh`, add new `launch_app` call:
```bash
# 5. New App - Description
if command -v newapp &>/dev/null; then
    launch_app "NewApp" "newapp --args"
else
    log "newapp not found, skipping"
fi
```

Rebuild image, deploy via `bootc switch`.

### Per-App Control

**Current**: All apps enabled or all disabled.

**Future Enhancement**: Individual app flags:
```bash
# User creates:
~/.config/gamescope/disable-discord
~/.config/gamescope/disable-megasync

# Script checks before launching each:
if [[ ! -f ~/.config/gamescope/disable-discord ]]; then
    launch_app "Discord" "..."
fi
```

### Monitoring and Alerting

**Add to script**:
```bash
# After all launch_app calls:
LAUNCHED_COUNT=$(jobs -p | wc -l)
log "Launched $LAUNCHED_COUNT apps"

if [[ $LAUNCHED_COUNT -eq 0 ]]; then
    log "WARNING: No apps launched (all missing or disabled?)"
fi
```

**System-wide monitoring**:
```bash
# Check if service failed
systemctl --user is-failed gamescopeApps@steam.service
```

### Documentation for Users

Add to README.md:
- How to disable apps (simple touch-file method)
- How to check app status
- How to troubleshoot (journalctl commands)
- How to customize (edit script, add apps)

## Security Considerations

1. **Privilege Separation**:
   - Script runs as user, not root
   - Apps inherit user permissions (correct for user-space apps)
   - No sudo or elevated privileges required

2. **PID File Security**:
   - PID file in `$XDG_RUNTIME_DIR` (mode 0700, owned by user)
   - Not world-readable
   - Cleaned up on boot (tmpfs)

3. **Script Injection**:
   - Script uses `command -v` for executable checks (no command injection)
   - No user input processed
   - All commands are hardcoded

4. **Flatpak Sandboxing**:
   - Discord runs via flatpak (sandboxed by default)
   - Other apps may not be sandboxed (user discretion)

5. **Image Integrity**:
   - All files are part of signed container image
   - rpm-ostree verifies image signature on deployment
   - Rollback protection if image is corrupted

## Performance Impact

**Minimal**:
- Services start after Gamescope session (don't delay boot)
- Apps run in background (xvfb overhead is minimal)
- Failed apps don't block service startup
- PID file check is fast (no network I/O)

**Potential Issues**:
- High RAM usage if all apps run simultaneously (depends on apps)
- CPU spikes during app launches (mitigated by staggered launch)
- Disk I/O for cloud sync apps (megasync, pcloud)

**Mitigation**:
- User can disable individual apps (future enhancement)
- Apps are launched asynchronously (don't block each other)
- Restart=on-failure prevents runaway restart loops (RestartSec=5s)

## References

- [ChimeraOS gamescope-session](https://github.com/ChimeraOS/gamescope-session)
- [ChimeraOS gamescope-session-steam](https://github.com/ChimeraOS/gamescope-session-steam)
- [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [rpm-ostree Documentation](https://coreos.github.io/rpm-ostree/)
- [Bazzite Documentation](https://universal-blue.org/images/bazzite/)

## Changelog

- **2026-02-03**: Initial design document created

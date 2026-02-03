# Gamescope Headless Apps - Implementation Approach

## Overview

This implementation launches background applications (cloud sync, chat, RGB control) alongside Gamescope/Steam sessions using **systemd user units** instead of overriding upstream session configuration files.

## Design Decision: Systemd Units (Low Maintenance)

For a personal image where minimizing long-term maintenance is the priority, systemd units are the better choice.

### Why Systemd Units?

✅ **No Upstream Overrides**
- Doesn't replace `/usr/share/gamescope-session-plus/sessions.d/steam`
- Drop-in only adds a dependency, doesn't modify upstream
- Independent of ChimeraOS steam session changes
- Zero maintenance when upstream updates

✅ **Better Reliability**
- Automatic restart on crash (`Restart=on-failure`)
- Rate limiting prevents restart loops
- Systemd process supervision
- Clean shutdown via control groups

✅ **Better Management**
- Dedicated unit logs: `journalctl --user -u gamescopeApps.service`
- Status at a glance: `systemctl --user status gamescopeApps.service`
- Easy to enable/disable: `systemctl --user mask/unmask`
- Better debugging experience

✅ **Session Isolation**
- Explicit conflict with Plasma (`Conflicts=plasma-workspace.target`)
- Bound to gamescope session lifecycle (`BindsTo=`)
- Automatic cleanup when switching sessions

### Why NOT Session Hooks?

❌ **High Maintenance**
- Must copy entire upstream steam session file (148 lines)
- Must sync whenever ChimeraOS updates their session
- Risk of divergence if we don't keep up
- Only 4 lines are ours, but we maintain everything

❌ **No Process Management**
- No automatic restart on crash
- No systemd supervision
- Manual intervention if something fails

## Implementation

### Files in Image

```
/usr/lib/systemd/user/gamescopeApps.service
  ↳ Main service unit that launches apps

/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf
  ↳ Drop-in that adds "Wants=gamescopeApps.service"
  ↳ Doesn't modify upstream, just adds dependency

/usr/lib/systemd/user-preset/90-bazzite-dx.preset
  ↳ Enables service by default for all users

/usr/libexec/startGamescopeApps.sh
  ↳ Script that launches individual apps
```

### How It Works

1. User logs into Gamescope/Steam session
2. `gamescope-session-plus@steam.service` starts
3. Drop-in (`10-apps.conf`) pulls in `gamescopeApps.service` via `Wants=`
4. Service checks for `~/.config/gamescope/disable-apps` flag
5. Script launches apps via xvfb-run
6. Apps run in systemd cgroup, supervised by systemd
7. On crash, systemd automatically restarts (up to 3 times per minute)
8. When session ends, service stops automatically

### User Control

```bash
# Disable (two methods)
touch ~/.config/gamescope/disable-apps              # Simple flag
systemctl --user mask gamescopeApps.service        # Systemd way

# Enable
rm ~/.config/gamescope/disable-apps
systemctl --user unmask gamescopeApps.service

# Manage
systemctl --user status gamescopeApps.service      # Check status
systemctl --user restart gamescopeApps.service     # Restart
journalctl --user -u gamescopeApps.service -f      # View logs
```

## Comparison with Session Hooks

| Aspect | Systemd Units (This) | Session Hooks |
|--------|---------------------|---------------|
| **Maintenance** | ✅ Zero (no upstream sync) | ❌ High (sync on updates) |
| **Upstream Changes** | ✅ Independent | ❌ Must track and merge |
| **Reliability** | ✅ Auto-restart on crash | ❌ No restart |
| **Process Management** | ✅ Systemd supervision | ❌ Basic fork/exec |
| **Logging** | ✅ Dedicated unit logs | ❌ Shared session logs |
| **Session Isolation** | ✅ Explicit conflicts | ✅ Natural (process tree) |
| **User Control** | ✅ Full systemd commands | ❌ Only flag file |
| **Complexity** | ⚠️ 4 files | ✅ 2 files |
| **Timing** | ⚠️ systemd scheduling | ✅ Guaranteed (hook) |

## For Personal Image Use

This implementation is optimized for:

✅ **Personal image** (not distribution)
- Enabled by default via preset
- Part of immutable image

✅ **Low maintenance priority**
- No upstream file overrides
- Independent of ChimeraOS changes
- Set and forget

✅ **Better reliability**
- Automatic restart on crash
- Systemd process management

## Adding Custom Apps

Edit `/usr/libexec/startGamescopeApps.sh`:

```bash
# 5. Your App - Description
if command -v myapp &>/dev/null; then
    if launch_app "MyApp" myapp --args; then
        ((APPS_LAUNCHED++))
    fi
else
    log "myapp not found, skipping"
fi
```

For Flatpak apps:

```bash
if flatpak list 2>/dev/null | grep -q com.example.MyApp; then
    if launch_app "MyApp" flatpak run com.example.MyApp; then
        ((APPS_LAUNCHED++))
    fi
fi
```

## Troubleshooting

### Service won't start

```bash
# Check status
systemctl --user status gamescopeApps.service

# Check if disabled
systemctl --user is-enabled gamescopeApps.service

# Check for disable flag
ls -la ~/.config/gamescope/disable-apps

# View full logs
journalctl --user -u gamescopeApps.service --since today
```

### Apps not launching

```bash
# Check what the script is doing
journalctl --user -u gamescopeApps.service -f

# Test script manually (from Gamescope session)
/usr/libexec/startGamescopeApps.sh

# Check if xvfb-run exists
command -v xvfb-run
```

### Service keeps restarting

Check logs for errors:
```bash
journalctl --user -u gamescopeApps.service -n 50
```

The service has rate limiting:
- Max 3 restarts per 60 seconds
- After that, it stops trying

## Migration from Session Hooks

If you were using the old approach (steam session file override):

**Old files** (removed):
- ❌ `/usr/share/gamescope-session-plus/sessions.d/steam`

**New files** (added):
- ✅ `/usr/lib/systemd/user/gamescopeApps.service`
- ✅ `/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf`
- ✅ `/usr/lib/systemd/user-preset/90-bazzite-dx.preset`

**No user action required** - the new approach is enabled by default.

## References

- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [ChimeraOS gamescope-session](https://github.com/ChimeraOS/gamescope-session)

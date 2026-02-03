# Gamescope Headless Apps - Config-File Driven Implementation

## Perfect for Personal Images

This implementation is optimized for **personal images** where the priority is **long-term low maintenance** and **ease of customization**.

## Key Design Principles

✅ **Config-File Driven** - Add/remove apps by editing a simple text file
✅ **No Upstream Overrides** - Doesn't modify ChimeraOS/Bazzite session files
✅ **Zero Maintenance** - Independent of upstream changes
✅ **Dead Simple** - One command per line, no code required
✅ **User Overridable** - System default + optional user customization

## How It Works

### Simple Config Format

```bash
# /etc/gamescope-apps.conf
# One command per line, comments start with #

megasync
flatpak run com.discordapp.Discord --start-minimized
pcloud
openrgb --startminimized
```

### Config File Locations

1. **System default** (shipped in image):
   ```
   /etc/gamescope-apps.conf
   ```

2. **User override** (optional, created at runtime):
   ```
   ~/.config/gamescope/apps.conf
   ```

User config completely replaces system config if present.

### Adding Apps

**In your image fork:**
```bash
# Edit system config
nano system_files/etc/gamescope-apps.conf

# Add your app
echo "your-app --args" >> system_files/etc/gamescope-apps.conf

# Rebuild image
```

**At runtime:**
```bash
# Create user config
cp /etc/gamescope-apps.conf ~/.config/gamescope/apps.conf

# Edit it
nano ~/.config/gamescope/apps.conf

# Restart service
systemctl --user restart gamescopeApps.service
```

### Removing Apps

**Temporary:**
```bash
# Comment out in config
# megasync
```

**Permanent:**
```bash
# Delete the line from config file
```

Then restart the service.

## Implementation Details

### Files in Image

```
/etc/gamescope-apps.conf
  ↳ Simple text config with default apps

/usr/lib/systemd/user/gamescopeApps.service
  ↳ Systemd service that manages the apps

/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf
  ↳ Drop-in that adds dependency (doesn't modify upstream!)

/usr/lib/systemd/user-preset/90-bazzite-dx.preset
  ↳ Enables service by default

/usr/libexec/startGamescopeApps.sh
  ↳ Script that reads config and launches apps
```

### No Upstream File Overrides

**What we DON'T do:**
- ❌ Override `/usr/share/gamescope-session-plus/sessions.d/steam`
- ❌ Modify any ChimeraOS files
- ❌ Fork upstream session configuration

**What we DO:**
- ✅ Add drop-in to gamescope-session-plus (just adds dependency)
- ✅ Provide our own service unit
- ✅ Use simple config file

## Why This Is Perfect for Your Use Case

### Personal Image Requirements

| Requirement | Solution |
|-------------|----------|
| Long-term low maintenance | No upstream overrides to sync |
| Easy to add/remove apps | Edit text file, no code |
| Config-file driven | `/etc/gamescope-apps.conf` |
| No forked sessions | Drop-in only, no modifications |
| Personal only | Optimized for single user |

### Comparison with Other Approaches

| Aspect | Config-File (This) | Session Hooks | Script Editing |
|--------|-------------------|---------------|----------------|
| **Maintenance** | ✅ Zero | ❌ High | ⚠️ Medium |
| **Add/Remove Apps** | ✅ Edit text file | ❌ Edit session file | ⚠️ Edit script |
| **Upstream Sync** | ✅ None needed | ❌ Must sync | ✅ None needed |
| **User Override** | ✅ Easy | ❌ Difficult | ⚠️ Copy script |
| **Simplicity** | ✅ Dead simple | ❌ Complex | ⚠️ Need bash |

## Usage Examples

### Minimal Setup

```bash
# /etc/gamescope-apps.conf
megasync
```

### Gaming Setup

```bash
# Cloud sync for saves
megasync

# Voice chat
flatpak run com.discordapp.Discord --start-minimized

# RGB control
openrgb --startminimized
```

### Power User Setup

```bash
# Multiple cloud providers
megasync
nextcloud --background
pcloud

# Communication
flatpak run com.discordapp.Discord --start-minimized
flatpak run com.slack.Slack --startup

# System utilities
openrgb --startminimized
coolercontrol
```

## Management

### Check Status

```bash
systemctl --user status gamescopeApps.service
```

### View Logs

```bash
# See what was launched
journalctl --user -u gamescopeApps.service -f

# Recent launches
journalctl --user -u gamescopeApps.service --since today
```

### Restart After Config Changes

```bash
systemctl --user restart gamescopeApps.service
```

### Disable Completely

```bash
# Method 1: Flag file
touch ~/.config/gamescope/disable-apps

# Method 2: Mask service
systemctl --user mask gamescopeApps.service
```

## Troubleshooting

### App Not Starting

```bash
# Check if command works
xvfb-run megasync  # Test manually

# Check logs
journalctl --user -u gamescopeApps.service | grep megasync
```

### Config Not Applied

```bash
# Verify config contents
cat /etc/gamescope-apps.conf
cat ~/.config/gamescope/apps.conf  # if exists

# Restart service
systemctl --user restart gamescopeApps.service
```

### Service Won't Start

```bash
# Check status
systemctl --user status gamescopeApps.service

# Check for disable flag
ls -la ~/.config/gamescope/disable-apps

# View errors
journalctl --user -u gamescopeApps.service -n 20
```

## Advantages Over Alternative Approaches

### vs Session Hooks (Overriding steam session)

**Session Hooks:**
- ❌ Must override 148-line upstream file
- ❌ Must sync when ChimeraOS updates
- ❌ High maintenance burden
- ❌ Hard to customize

**Config-File:**
- ✅ No upstream file overrides
- ✅ Zero maintenance (independent)
- ✅ Edit simple text file
- ✅ User can override

### vs Script Editing

**Script Editing:**
- ⚠️ Must edit bash code to add apps
- ⚠️ Need to understand script structure
- ⚠️ Hard for non-programmers

**Config-File:**
- ✅ One command per line
- ✅ No code knowledge needed
- ✅ Anyone can edit

## Future-Proof

This implementation is **future-proof** because:

1. **No upstream dependencies** - ChimeraOS can change their session however they want
2. **Config-driven** - Your customizations are in a text file, not code
3. **Drop-in approach** - We only add, never modify
4. **Standard systemd** - Uses well-established patterns

## Maintenance Checklist

### When Building Your Image

- [ ] Edit `system_files/etc/gamescope-apps.conf` with your default apps
- [ ] Build and deploy image
- [ ] Test that apps launch in Gamescope session

### At Runtime

- [ ] Create `~/.config/gamescope/apps.conf` if you want personal changes
- [ ] Restart service after config changes
- [ ] Check logs to verify apps launched

### Never Needed

- ❌ Sync with upstream ChimeraOS changes
- ❌ Edit bash scripts
- ❌ Rebase session configuration
- ❌ Maintain forked files

## Summary

This is the **ideal solution** for a personal image where you want:

✅ **Minimum maintenance** - Set and forget
✅ **Easy customization** - Edit text file
✅ **No upstream conflicts** - Independent
✅ **Config-driven** - As requested
✅ **Future-proof** - Won't break on updates

Perfect for your use case!

## Questions?

- **Can I use shell variables?** - No, but you can use wrapper scripts
- **What about complex logic?** - Create wrapper scripts and call them from config
- **How do I share config between machines?** - Version control `~/.config/gamescope/apps.conf`
- **Can I have different configs per session?** - Not directly, but you can use wrapper scripts with conditionals

## Related Documentation

- `IMPLEMENTATION.md` - Technical details
- `README.md` - User-facing documentation
- Config file: `/etc/gamescope-apps.conf` - Example configuration

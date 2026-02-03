# Session Hooks vs Systemd Units: Comprehensive Comparison

## The Question

You proposed a systemd-based approach with user units and asked: **"How is it better than this approach?"**

This is an excellent question that deserves a thorough, honest answer. Let's compare both approaches fairly.

## Executive Summary

**Neither approach is universally "better"** - they serve different use cases:

| Use Case | Best Approach |
|----------|---------------|
| **Immutable image with default-enabled apps** | Session Hooks (current) |
| **User-installed, opt-in customization** | Systemd Units (your proposal) |
| **Maximum reliability & restart capability** | Systemd Units (your proposal) |
| **Simplest implementation** | Session Hooks (current) |
| **Most user control** | Systemd Units (your proposal) |

## Detailed Comparison

### Current Implementation: Session Hooks

**What it is:**
- Modifies `/usr/share/gamescope-session-plus/sessions.d/steam` (system file)
- Adds code to `post_gamescope_start()` hook
- Calls `/usr/libexec/startGamescopeApps.sh` in background

**File Locations:**
```
/usr/share/gamescope-session-plus/sessions.d/steam  # Part of immutable image
/usr/libexec/startGamescopeApps.sh                  # Part of immutable image
```

### Proposed Implementation: Systemd Units

**What it is:**
- User systemd units in `~/.config/systemd/user/`
- Drop-in override for gamescope-session-plus service
- Script in `~/Scripts/`

**File Locations:**
```
~/.config/systemd/user/gamescopeApps.service                              # User space
~/.config/systemd/user/gamescope-session-plus@.service.d/override.conf   # User space
~/Scripts/startGamescopeApps.sh                                          # User space
```

## Feature-by-Feature Comparison

### 1. Reliability & Error Handling

#### Session Hooks (Current) ❌ Weaker
```bash
/usr/libexec/startGamescopeApps.sh &  # Fire and forget
```
- **No automatic restart** if apps crash
- **No systemd supervision** of processes
- **Manual intervention** required if something fails
- Apps run as children of gamescope-session process

**Your Proposal** ✅ **WINNER**
```ini
Restart=on-failure
RestartSec=5
StartLimitBurst=3
StartLimitIntervalSec=60
```
- Automatic restart on crash
- Rate limiting to prevent restart loops
- Systemd manages process lifecycle
- Better process isolation with control groups

**Verdict**: Your systemd approach is significantly more reliable.

### 2. Conflict Resolution (Plasma Session)

#### Session Hooks (Current) ✅ Simple
- Apps stop when gamescope-session ends
- Natural lifecycle - no explicit conflict handling needed
- Relies on process tree termination

**Your Proposal** ✅ **WINNER** (More Explicit)
```ini
Conflicts=plasma-workspace.target
BindsTo=gamescope-session-plus@steam.service
StopWhenUnneeded=yes
```
- **Explicit conflict** with Plasma session
- **Guaranteed cleanup** when switching sessions
- **Clear dependency chain** via BindsTo
- Better prevents duplicate launches

**Verdict**: Your approach has better session isolation and conflict handling.

### 3. Immutable Image Integration

#### Session Hooks (Current) ✅ **WINNER**
```
system_files/usr/share/...        # Baked into image
system_files/usr/libexec/...      # Baked into image
```
- **Part of the image** - rolls back atomically
- **Default for all users** - no setup required
- **No per-user installation** needed
- Image updates = automatic updates

**Your Proposal** ❌ Weaker for Images
```
~/.config/systemd/user/...        # User space (not in image)
~/Scripts/...                     # User space (not in image)
```
- **Not part of image** - lives in /var/home
- **Requires setup** for each user (or template)
- **Doesn't roll back** with image
- Must use `/etc/skel/` for new user defaults

**Verdict**: Session hooks are better for immutable image distribution.

### 4. User Customization

#### Session Hooks (Current) ❌ Limited
- **Disable**: Create `~/.config/gamescope/disable-apps` (simple flag)
- **Enable**: Remove the flag
- **Customize**: Not easy - would need to override the system file

**Your Proposal** ✅ **WINNER**
```bash
systemctl --user enable gamescopeApps.service   # Enable
systemctl --user disable gamescopeApps.service  # Disable
systemctl --user restart gamescopeApps.service  # Restart
systemctl --user status gamescopeApps.service   # Status
journalctl --user -u gamescopeApps.service -f   # Logs
```
- **Full systemd control** - enable/disable/restart
- **Easy to customize** - edit your own unit file
- **Better debugging** - dedicated unit logs
- **User can override** anything in their space

**Verdict**: Your approach gives users much more control.

### 5. Complexity

#### Session Hooks (Current) ✅ **WINNER**
**Files**: 2
- `/usr/share/gamescope-session-plus/sessions.d/steam` (148 lines, mostly upstream)
- `/usr/libexec/startGamescopeApps.sh` (160 lines)

**Concepts**: 1
- Session hooks (straightforward callback)

**Your Proposal** ❌ More Complex
**Files**: 3
- `~/.config/systemd/user/gamescopeApps.service` (40+ lines)
- `~/.config/systemd/user/gamescope-session-plus@.service.d/override.conf` (15+ lines)
- `~/Scripts/startGamescopeApps.sh` (80+ lines)

**Concepts**: Multiple
- Systemd unit files
- Drop-in overrides
- Service dependencies (Wants, BindsTo, Conflicts)
- Targets (graphical-session.target, plasma-workspace.target)
- Conditions (ConditionPathExists)

**Verdict**: Session hooks are simpler to understand and implement.

### 6. Timing & Ordering

#### Session Hooks (Current) ✅ **WINNER**
```bash
post_gamescope_start() {
    # Runs HERE: after Gamescope ready, before Steam starts
    /usr/libexec/startGamescopeApps.sh &
}
```
- **Perfect timing** - guaranteed to run at the right moment
- **No race conditions** - hook executes synchronously
- **Environment is set** - all session vars available

**Your Proposal** ❌ Potential Race Conditions
```ini
After=graphical-session.target
After=gamescope-session-plus@steam.service
```
- **Not guaranteed** - systemd schedules independently
- **Race conditions possible** - Steam might start first
- **Environment may differ** - not sourced from session

**Verdict**: Session hooks have better timing guarantees.

### 7. Logging & Debugging

#### Session Hooks (Current) ❌ Shared Journal
```bash
echo "[bazzite-dx] Starting headless applications" >&2
```
- Logs to gamescope-session-plus journal
- **Harder to filter** - mixed with other session logs
- **No dedicated unit** to query

**Your Proposal** ✅ **WINNER**
```ini
StandardOutput=journal
StandardError=journal
```
```bash
journalctl --user -u gamescopeApps.service -f  # Dedicated logs
systemctl --user status gamescopeApps.service  # Quick status
```
- **Dedicated journal unit** - easy to filter
- **Systemd status** - see state at a glance
- **Better debugging** experience

**Verdict**: Your approach has better logging and debugging.

### 8. Process Management

#### Session Hooks (Current) ❌ Basic
```bash
# Launch in background
/usr/libexec/startGamescopeApps.sh &

# Apps launched via xvfb-run in script
xvfb-run -a -s "-screen 0 1024x768x24" myapp &
```
- Apps are children of session process
- **No restart on crash**
- **No resource limits**
- Manual cleanup if something goes wrong

**Your Proposal** ✅ **WINNER**
```ini
Type=exec
KillMode=control-group
TimeoutStartSec=15
TimeoutStopSec=10
```
```bash
sleep infinity  # Keep script running for cgroup
```
- Apps in dedicated **control group**
- **Timeouts** prevent hanging
- **Proper cleanup** with KillMode
- **Systemd supervision**

**Verdict**: Your approach has much better process management.

### 9. Maintenance

#### Session Hooks (Current) ❌ Must Sync with Upstream
- Must copy entire upstream steam session file
- **Must update** when ChimeraOS changes upstream
- Risk of drift if we don't keep up
- Only 4 lines are ours, but we maintain 148 lines

**Your Proposal** ✅ **WINNER**
- **No upstream file override** required
- Only maintain our own units
- **Drop-in override** is surgical (only what we need)
- Upstream updates don't affect us

**Verdict**: Your approach is easier to maintain long-term.

### 10. Distribution

#### Session Hooks (Current) ✅ **WINNER** for Images
- **One-click deployment** - built into image
- **No user action** required
- **Consistent across users**
- **Rollback works** atomically

**Your Proposal** ❌ Complex for Images
- **Must template** to `/etc/skel/.config/systemd/user/`
- **Must enable** by default somehow
- **Won't work** for existing users without migration
- **More complex** to distribute in image

**Verdict**: Session hooks are better for default-enabled distribution.

## Your Implementation Analysis

Your proposed systemd implementation is **excellent** and shows several advanced techniques:

### ✅ What You Got Right

1. **ConditionPathExists** - Prevents running if disabled
2. **Conflicts=plasma-workspace.target** - Smart session isolation
3. **BindsTo=gamescope-session-plus** - Proper lifecycle binding
4. **StopWhenUnneeded=yes** - Clean shutdown behavior
5. **Restart=on-failure** - Reliability
6. **StartLimitBurst=3** - Rate limiting
7. **KillMode=control-group** - Proper cleanup
8. **flock** in script - Prevents duplicates
9. **sleep infinity** - Keeps cgroup alive
10. **TimeoutStartSec/StopSec** - Prevents hangs

This is a **production-quality** systemd implementation.

### ⚠️ Potential Issues

1. **User-space location** - Not ideal for immutable image
   ```
   ~/.config/systemd/user/  # Not part of image
   ~/Scripts/               # Not part of image
   ```
   **Fix**: Could use `/usr/lib/systemd/user/` for image distribution

2. **Manual enablement** - How do users know to enable it?
   ```
   systemctl --user enable gamescopeApps.service  # Manual step
   ```
   **Fix**: Could preset with systemd preset files

3. **Requires graphical-session.target** - May not exist in all sessions
   ```ini
   After=graphical-session.target
   ```
   **Fix**: This is correct for user units

## Hybrid Approach: Best of Both Worlds?

We could combine approaches:

```
Image ships:
  /usr/lib/systemd/user/gamescopeApps@.service           # System-provided unit
  /usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf  # Drop-in
  /usr/libexec/startGamescopeApps.sh                     # Script

User can override:
  ~/.config/systemd/user/gamescopeApps@.service.d/       # Personal customization
```

**Benefits**:
- ✅ Part of image (default for all users)
- ✅ Systemd reliability & restart
- ✅ Users can override with drop-ins
- ✅ Better logging & debugging

**Downsides**:
- ❌ More complex than session hooks
- ❌ 3+ files instead of 2
- ❌ Timing less guaranteed than hooks

## Recommendation

### For Bazzite-DX Image: Session Hooks (Current) ✅

**Why:**
1. **Image distribution** - It's part of the immutable image
2. **Simplicity** - 2 files, straightforward
3. **Default for all** - No setup required
4. **Perfect timing** - Guaranteed execution order
5. **Standard pattern** - How Bazzite does session customization

**Accept limitations:**
- No automatic restart on crash (apps are generally stable)
- Shared journal logs (can filter with grep)
- Less user control (but most users just want it to work)

### For Your Personal Setup: Systemd Units (Your Proposal) ✅

**Why:**
1. **Better reliability** - Automatic restart
2. **More control** - Full systemd management
3. **Better debugging** - Dedicated unit logs
4. **Easier maintenance** - No upstream sync needed
5. **Session isolation** - Explicit conflict handling

**Your implementation is excellent** - you clearly understand systemd well.

## Switching to Systemd Units: If We Want To

If you believe the systemd approach is better for Bazzite-DX, here's how to do it:

### Changes Required

1. **Remove session hook approach**:
   ```bash
   rm system_files/usr/share/gamescope-session-plus/sessions.d/steam
   ```

2. **Add systemd units to image**:
   ```
   system_files/usr/lib/systemd/user/gamescopeApps.service
   system_files/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-apps.conf
   system_files/usr/libexec/startGamescopeApps.sh  # Keep this
   ```

3. **Add systemd preset** (enable by default):
   ```
   system_files/usr/lib/systemd/user-preset/90-bazzite-dx.preset
   ```
   ```ini
   enable gamescopeApps.service
   ```

4. **Update Containerfile**:
   ```dockerfile
   # Enable the service by default
   RUN systemctl --user --global enable gamescopeApps.service
   ```

### Would it be worth it?

**Arguments FOR switching**:
- ✅ Better reliability (restart on crash)
- ✅ Better debugging (dedicated logs)
- ✅ Better session isolation (conflicts)
- ✅ No upstream sync needed
- ✅ More professional approach

**Arguments AGAINST switching**:
- ❌ More complexity (3 files, systemd concepts)
- ❌ Timing less guaranteed (race conditions possible)
- ❌ Requires more container setup (presets, global enable)
- ❌ Not the ChimeraOS pattern (they use hooks)
- ❌ Current approach already works

## My Honest Assessment

Your systemd approach is **technically superior** in several ways:
1. More reliable (restart on failure)
2. Better process management
3. Better logging
4. Easier to maintain (no upstream sync)
5. Better session isolation

However, the session hooks approach is **simpler and more appropriate** for:
1. Immutable image distribution
2. Following ChimeraOS patterns
3. Guaranteed timing
4. Minimal complexity

### The Real Question

**What's more important for Bazzite-DX?**

A. **Simplicity and default-works** → Keep session hooks
B. **Reliability and control** → Switch to your systemd approach

For a personal setup where you want maximum control and reliability, your systemd approach is better.

For an image that many users will consume where we want it to "just work" with minimal complexity, session hooks are better.

## Conclusion

**Your systemd implementation is excellent** and for many use cases (especially personal setups) it's the better choice. You clearly understand systemd well and your implementation is production-quality.

For Bazzite-DX as an immutable image, I still believe session hooks are the right choice because:
- ✅ Simpler (fewer moving parts)
- ✅ Part of the image (atomic updates/rollbacks)
- ✅ Follows ChimeraOS patterns
- ✅ Perfect timing guarantees

But if you want to switch to systemd units, I can help implement that. Your approach would give users more control and reliability, at the cost of some additional complexity.

## Your Choice

What would you prefer?

1. **Keep session hooks** (current) - simpler, standard for images
2. **Switch to systemd units** (your proposal) - more reliable, better control
3. **Hybrid approach** - systemd units baked into image

Let me know and I'll implement whichever you prefer!

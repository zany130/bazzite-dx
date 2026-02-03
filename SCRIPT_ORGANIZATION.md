# Script Organization - Linux FHS Standards

This document explains where different types of scripts should be located in the Bazzite-DX image, following the Linux Filesystem Hierarchy Standard (FHS).

## Directory Purposes

### `/usr/libexec/` - Internal Helper Programs

**Purpose**: Executable programs meant to be called by other programs (systemd services, etc.), NOT by users directly.

**Scripts in this directory:**
- ✅ `startGamescopeApps.sh` - Called only by `gamescopeApps.service`
- ✅ `LG_Buddy_Startup` - Called only by `LG_Buddy.service` (ExecStart)
- ✅ `LG_Buddy_Shutdown` - Called only by `LG_Buddy.service` (ExecStop)

**Why here:**
- These are internal implementation details of services
- Users should never call these directly
- Keeps `/usr/local/bin/` clean for actual user commands
- Standard FHS location for helper programs

### `/usr/local/sbin/` - Local System Administration Programs

**Purpose**: System administration commands that users run directly (often with sudo).

**Scripts in this directory:**
- ✅ `reset-video-port` - User runs manually when video port needs reset

**Why here:**
- Users execute this directly: `sudo reset-video-port DP-2`
- Administrative tool (requires root/sudo)
- Not a service helper - actual user-facing command

### `/usr/local/bin/` - Local User Programs

**Purpose**: User-facing commands that don't require root privileges.

**Scripts in this directory:**
- Currently empty (we moved LG Buddy scripts out)

**When to use:**
- User-facing tools that don't need sudo
- Commands users type at terminal
- Not for service helpers

## Quick Reference Guide

### Is your script...

**Only called by systemd services?**
→ Put it in `/usr/libexec/`

**Run directly by users with sudo?**
→ Put it in `/usr/local/sbin/`

**Run directly by users without sudo?**
→ Put it in `/usr/local/bin/`

**Part of a system package?**
→ Use `/usr/bin/`, `/usr/sbin/`, or `/usr/libexec/` (no `/local/`)

## Examples from This Repository

### Good: Service Helper Scripts

```bash
# LG_Buddy.service calls these
ExecStart=/usr/libexec/LG_Buddy_Startup
ExecStop=/usr/libexec/LG_Buddy_Shutdown

# gamescopeApps.service calls this
ExecStart=/usr/libexec/startGamescopeApps.sh
```

These scripts are implementation details - users never see them.

### Good: User Admin Tools

```bash
# User runs this directly
$ sudo reset-video-port DP-2
```

This is a user-facing administrative tool.

## Why This Organization Matters

✅ **Clarity**: Users know which commands they can run
✅ **FHS Compliance**: Follows Linux standards
✅ **Maintenance**: Easy to understand what's internal vs. public
✅ **Consistency**: Same pattern throughout the system

## Historical Note

Previously, `LG_Buddy_Startup` and `LG_Buddy_Shutdown` were in `/usr/local/bin/`, which suggested they were user commands. Since users never invoke these directly (only systemd does), they were moved to `/usr/libexec/` to better reflect their purpose as internal service helpers.

## References

- [Filesystem Hierarchy Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html)
- [FHS: /usr/libexec](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch04s07.html)
- [FHS: /usr/local](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch04s09.html)

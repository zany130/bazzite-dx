#!/bin/bash
# ============================================================================
# Gamescope Headless Apps Launcher
# Starts additional background applications for Gamescope sessions
# ============================================================================
# This script is called from gamescopeApps.service (systemd user unit).
#
# It launches applications that need to run in the background alongside the
# Gamescope/Steam session but don't need to be visible in the Gamescope
# compositor (e.g., sync clients, chat apps, RGB control).
#
# Design Notes:
#   - Uses xvfb-run to provide virtual X11 display for GUI apps
#   - Managed by systemd (automatic restart on crash)
#   - Check for disable flag to allow per-user opt-out
#   - Gracefully handles missing applications (skip with warning)
#   - Logs to systemd journal
#   - Keeps running (sleep infinity) to maintain systemd cgroup
# ============================================================================

set -euo pipefail

# Configuration
DISABLE_FLAG="${HOME}/.config/gamescope/disable-apps"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope-apps.lock"
LOG_TAG="gamescopeApps"

# Logging helper
log() {
    echo "[$LOG_TAG] $*" >&2
}

# Check if user has opted out (systemd should also check via ConditionPathExists)
if [[ -f "$DISABLE_FLAG" ]]; then
    log "Headless apps disabled by user (found: $DISABLE_FLAG)"
    exit 0
fi

# Ensure XDG_RUNTIME_DIR is set
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    log "ERROR: XDG_RUNTIME_DIR not set"
    exit 1
fi

# Ensure xvfb-run exists
if ! command -v xvfb-run &>/dev/null; then
    log "ERROR: xvfb-run not found"
    exit 1
fi

# Prevent duplicate runs using flock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another instance is already running, exiting"
    exit 0
fi

log "Starting headless apps (PID: $$)"

# ============================================================================
# Launch Applications
# ============================================================================
# Each app is launched via xvfb-run which provides a virtual X11 display.
# This is necessary for GUI applications that expect X11 but don't need to
# be visible in Gamescope (which uses Wayland internally).
#
# xvfb-run options:
#   -a: Auto-select display number (avoids conflicts)
#   -s: Server arguments for Xvfb (screen size and color depth)
# ============================================================================

# Function to launch app via xvfb-run
launch_app() {
    local app_name="$1"
    shift
    
    log "Launching: $app_name"
    
    # Launch in background via xvfb-run
    # Apps will be children of this script, kept in the systemd cgroup
    if ! xvfb-run -a -s "-screen 0 1024x768x24" "$@" &>/dev/null &
    then
        log "WARNING: Failed to launch $app_name"
        return 1
    fi
    
    local pid=$!
    log "Started: $app_name (PID: $pid)"
    
    return 0
}

# ============================================================================
# Application Definitions
# ============================================================================
# Add or remove applications here. Each app is checked for existence before
# launching, so missing apps are gracefully skipped.
# ============================================================================

APPS_LAUNCHED=0

# 1. MEGAsync - Cloud storage sync
# Automatically syncs MEGA cloud storage in the background
if command -v megasync &>/dev/null; then
    if launch_app "megasync" megasync; then
        ((APPS_LAUNCHED++))
    fi
else
    log "megasync not found, skipping"
fi

# 2. Discord - Flatpak version
# Chat application, started minimized
if flatpak list 2>/dev/null | grep -q com.discordapp.Discord; then
    if launch_app "Discord" flatpak run com.discordapp.Discord --start-minimized; then
        ((APPS_LAUNCHED++))
    fi
else
    log "Discord flatpak not found, skipping"
fi

# 3. pCloud - Cloud storage (if installed)
# Alternative cloud storage client
if command -v pcloud &>/dev/null; then
    if launch_app "pCloud" pcloud; then
        ((APPS_LAUNCHED++))
    fi
else
    log "pcloud not found, skipping"
fi

# 4. OpenRGB - RGB lighting control
# Controls RGB lighting on peripherals and components
if command -v openrgb &>/dev/null; then
    if launch_app "OpenRGB" openrgb --startminimized; then
        ((APPS_LAUNCHED++))
    fi
else
    log "openrgb not found, skipping"
fi

# ============================================================================
# Add more applications here following the same pattern:
# ============================================================================
# if command -v myapp &>/dev/null; then
#     if launch_app "MyApp" "myapp --args"; then
#         ((APPS_LAUNCHED++))
#     fi
# else
#     log "myapp not found, skipping"
# fi
# ============================================================================

log "Successfully launched $APPS_LAUNCHED application(s)"

# Keep script running to maintain systemd cgroup
# This ensures all child processes stay in the service's control group
# and are properly managed/cleaned up by systemd
log "Keeping service alive (sleep infinity)"
sleep infinity

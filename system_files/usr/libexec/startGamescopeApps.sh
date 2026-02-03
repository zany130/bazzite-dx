#!/bin/bash
# ============================================================================
# Gamescope Headless Apps Launcher - Config-Driven
# ============================================================================
# Launches background applications for Gamescope sessions from config files.
# This script reads simple config files and launches each command via xvfb-run.
#
# Config files (processed in order, later overrides earlier):
#   1. /etc/gamescope-apps.conf        (system default, part of image)
#   2. ~/.config/gamescope/apps.conf   (user override, optional)
#
# Config format:
#   - One command per line
#   - Lines starting with # are comments
#   - Empty lines are ignored
#   - Commands are executed as-is via xvfb-run
#
# Managed by: gamescopeApps.service (systemd user unit)
# Disable: touch ~/.config/gamescope/disable-apps
# ============================================================================

set -euo pipefail

# Configuration
DISABLE_FLAG="${HOME}/.config/gamescope/disable-apps"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope-apps.lock"
LOG_TAG="gamescopeApps"

# Config file locations
SYSTEM_CONFIG="/etc/gamescope-apps.conf"
USER_CONFIG="${HOME}/.config/gamescope/apps.conf"

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

log "Starting headless apps launcher (PID: $$)"

# Function to read and parse config file
read_config() {
    local config_file="$1"
    local commands=()
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    log "Reading config: $config_file"
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Add command to array
        commands+=("$line")
    done < "$config_file"
    
    printf '%s\n' "${commands[@]}"
}

# Function to launch app via xvfb-run
launch_app() {
    local app_cmd="$*"
    local app_name="${1%% *}"  # First word is the app name
    
    log "Launching: $app_cmd"
    
    # Launch in background via xvfb-run
    # Apps will be children of this script, kept in the systemd cgroup
    if ! xvfb-run -a -s "-screen 0 1024x768x24" $app_cmd &>/dev/null &
    then
        log "WARNING: Failed to launch: $app_cmd"
        return 1
    fi
    
    local pid=$!
    log "Started: $app_name (PID: $pid, command: $app_cmd)"
    
    return 0
}

# ============================================================================
# Read Configuration Files
# ============================================================================

APPS_LAUNCHED=0
declare -a ALL_COMMANDS

# Read system config (if exists)
if [[ -f "$SYSTEM_CONFIG" ]]; then
    log "Loading system config: $SYSTEM_CONFIG"
    mapfile -t SYSTEM_COMMANDS < <(read_config "$SYSTEM_CONFIG")
    ALL_COMMANDS+=("${SYSTEM_COMMANDS[@]}")
fi

# Read user config (if exists) - this can override or add to system config
if [[ -f "$USER_CONFIG" ]]; then
    log "Loading user config: $USER_CONFIG"
    log "User config will be used instead of system config"
    # Clear system commands if user has their own config
    ALL_COMMANDS=()
    mapfile -t USER_COMMANDS < <(read_config "$USER_CONFIG")
    ALL_COMMANDS+=("${USER_COMMANDS[@]}")
fi

# Check if we have any commands to run
if [[ ${#ALL_COMMANDS[@]} -eq 0 ]]; then
    log "No commands found in config files"
    log "Hint: Edit $SYSTEM_CONFIG or create $USER_CONFIG"
    exit 0
fi

log "Found ${#ALL_COMMANDS[@]} command(s) to launch"

# ============================================================================
# Launch Applications
# ============================================================================

for cmd in "${ALL_COMMANDS[@]}"; do
    if launch_app $cmd; then
        ((APPS_LAUNCHED++))
    fi
done

log "Successfully launched $APPS_LAUNCHED/${#ALL_COMMANDS[@]} application(s)"

# ============================================================================
# Keep Service Running
# ============================================================================
# Keep script running to maintain systemd cgroup
# This ensures all child processes stay in the service's control group
# and are properly managed/cleaned up by systemd

log "Service active, keeping processes alive (sleep infinity)"
sleep infinity

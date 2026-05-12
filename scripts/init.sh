#!/bin/bash
set -e

# =============================================================================
# init.sh — Container entrypoint
# 1. Validate environment variables
# 2. Create runtime user/group from PUID/PGID
# 3. Fix volume ownership
# 4. Run SteamCMD install/update (if UPDATE_ON_START=true)
# 5. Drop privileges and launch server start script
# =============================================================================

source /opt/pz/scripts/functions.sh

log "========================================================"
log " Project Zomboid ARM64 Server — Entrypoint"
log "========================================================"

# --- Defaults ---
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
MEMORY="${MEMORY:-2G}"
MEMORY_XMX_GB="${MEMORY_XMX_GB:-}"
MEMORY_XMS_GB="${MEMORY_XMS_GB:-}"
RCON_PORT="${RCON_PORT:-27015}"
RCON_PASSWORD="${RCON_PASSWORD:-changeme}"
UPDATE_ON_START="${UPDATE_ON_START:-true}"
USE_JAVA_FALLBACK="${USE_JAVA_FALLBACK:-false}"
GENERATE_SETTINGS="${GENERATE_SETTINGS:-true}"
SERVER_NAME="${SERVER_NAME:-pzserver}"
DISABLE_STEAM="${DISABLE_STEAM:-false}"
JAVA_EXTRA_ARGS="${JAVA_EXTRA_ARGS:-}"
ARM64_DEVICE="${ARM64_DEVICE:-}"

# BRANCH: accept SERVER_BRANCH as backwards-compatible alias
BRANCH="${BRANCH:-${SERVER_BRANCH:-}}"
export BRANCH

# SERVER_PUBLIC: compose-safe primary; PUBLIC is backwards-compatible alias
SERVER_PUBLIC="${SERVER_PUBLIC:-${PUBLIC:-true}}"
export SERVER_PUBLIC

export PUID PGID MEMORY MEMORY_XMX_GB MEMORY_XMS_GB
export RCON_PORT RCON_PASSWORD UPDATE_ON_START USE_JAVA_FALLBACK
export GENERATE_SETTINGS SERVER_NAME DISABLE_STEAM JAVA_EXTRA_ARGS ARM64_DEVICE
export SERVER_PUBLIC

log "Configuration:"
log "  PUID=$PUID  PGID=$PGID  MEMORY=${MEMORY:-inherit}"
[[ -n "$MEMORY_XMX_GB" ]] && log "  MEMORY_XMX_GB=$MEMORY_XMX_GB"
log "  SERVER_NAME=$SERVER_NAME  RCON_PORT=$RCON_PORT"
log "  UPDATE_ON_START=$UPDATE_ON_START  GENERATE_SETTINGS=$GENERATE_SETTINGS"
log "  USE_JAVA_FALLBACK=$USE_JAVA_FALLBACK  DISABLE_STEAM=$DISABLE_STEAM"
[[ -n "$ARM64_DEVICE" ]] && log "  ARM64_DEVICE=$ARM64_DEVICE"
[[ -n "$BRANCH" ]] && log "  BRANCH=$BRANCH"

# --- Create runtime group ---
if ! getent group "$PGID" &>/dev/null; then
    groupadd -g "$PGID" pzuser
    log "Created group pzuser with GID $PGID"
fi

# --- Create runtime user ---
if ! getent passwd "$PUID" &>/dev/null; then
    useradd -u "$PUID" -g "$PGID" -d /home/pzuser -m -s /bin/bash pzuser
    log "Created user pzuser with UID $PUID"
fi

# --- Fix volume ownership ---
log "Fixing volume permissions..."
chown -R "$PUID:$PGID" /project-zomboid /project-zomboid-config /steamapps 2>/dev/null || \
    log "WARNING: Some volume paths not mounted, skipping chown"

# --- Run SteamCMD install/update ---
if [[ "${DISABLE_STEAM,,}" == "true" ]]; then
    log "DISABLE_STEAM=true — skipping SteamCMD entirely"
elif [[ "${UPDATE_ON_START,,}" == "true" ]]; then
    log "UPDATE_ON_START=true — running SteamCMD install/update"
    gosu "$PUID:$PGID" /opt/pz/scripts/install.scmd
    log "SteamCMD update complete"
else
    log "UPDATE_ON_START=false — skipping SteamCMD update"
fi

# --- Drop privileges and start server ---
log "Starting Project Zomboid server..."
exec gosu "$PUID:$PGID" /opt/pz/scripts/start-arm64.sh

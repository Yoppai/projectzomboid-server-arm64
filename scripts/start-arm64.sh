#!/bin/bash
set -e

# =============================================================================
# start-arm64.sh — Project Zomboid server launcher for ARM64 via Box64
#
# Responsibilities:
# - Export Box64 dynarec environment variables for emulation performance
# - Patch ProjectZomboid64.json with MEMORY heap settings
# - Trap SIGTERM/SIGINT → RCON quit with timed fallback to SIGTERM → SIGKILL
# - Launch ProjectZomboid64 under Box64 (or Java fallback)
# =============================================================================

source /opt/pz/scripts/functions.sh

log "========================================================"
log " Project Zomboid ARM64 Server — Launcher"
log "========================================================"

# --- Box64 dynarec tuning ---
SERVER_DIR="/project-zomboid"
PZ_JAVA_PATH="${SERVER_DIR}/jre64/bin:${SERVER_DIR}/jre/bin:${SERVER_DIR}/java/bin"
export BOX64_DYNAREC_BIGBLOCK=${BOX64_DYNAREC_BIGBLOCK:-1}
export BOX64_DYNAREC_BLEEDING_EDGE=${BOX64_DYNAREC_BLEEDING_EDGE:-0}
export BOX64_DYNAREC_BB_LOOP=${BOX64_DYNAREC_BB_LOOP:-1}
export BOX64_DYNAREC_FORWARD=${BOX64_DYNAREC_FORWARD:-1}
export BOX64_DYNAREC_STRONGMEM=${BOX64_DYNAREC_STRONGMEM:-1}
export BOX64_PATH="${PZ_JAVA_PATH}:/usr/local/bin:/usr/bin:/bin"
export PATH="${PZ_JAVA_PATH}:${PATH}"
PZ_LIBRARY_PATH="${SERVER_DIR}:${SERVER_DIR}/linux64:${SERVER_DIR}/natives:${SERVER_DIR}/jre64/lib:${SERVER_DIR}/jre64/lib/server:${SERVER_DIR}/jre/lib:${SERVER_DIR}/jre/lib/server"
export BOX64_LD_LIBRARY_PATH="${PZ_LIBRARY_PATH}:${BOX64_LD_LIBRARY_PATH:-/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:/usr/local/lib}"
export LD_LIBRARY_PATH="${PZ_LIBRARY_PATH}:${LD_LIBRARY_PATH:-}"

log "Box64 env:"
log "  BOX64_DYNAREC_BIGBLOCK=$BOX64_DYNAREC_BIGBLOCK"
log "  BOX64_DYNAREC_BLEEDING_EDGE=$BOX64_DYNAREC_BLEEDING_EDGE"

# --- Memory config ---
# Resolve memory: MEMORY_XMX_GB/MEMORY_XMS_GB preferred, MEMORY fallback
read -r XMX_VAL XMS_VAL <<< "$(resolve_memory)"
log "Memory: Xmx=${XMX_VAL} Xms=${XMS_VAL}"

# Patch server JSON with resolved values
patch_memory_json "$XMX_VAL" "$XMS_VAL"

# Install PanelBridge mod (if enabled) — runs before INI patching
# If download fails, PANEL_BRIDGE_ENABLED is set to false so INI stays clean
install_panelbridge || true

# Patch server.ini with full env settings (gated by GENERATE_SETTINGS)
# Admin/RCON/minimal settings always written for server start
patch_server_ini

# --- Paths ---
ZOMBOID64="${SERVER_DIR}/ProjectZomboid64"

if [[ ! -f "$ZOMBOID64" ]]; then
    log "WARNING: ${ZOMBOID64} not found — server may not be installed yet"
    log "If first run, SteamCMD will download on next restart with UPDATE_ON_START=true"
fi

# --- Signal handling ---
SERVER_PID=0

shutdown_handler() {
    log "SIGTERM received — initiating graceful shutdown"

    # 1) Try explicit world save before shutdown
    if rcon_send "save"; then
        log "RCON save command sent successfully"
        sleep 3
    else
        log "RCON save failed — continuing shutdown"
    fi

    # 2) Try RCON quit
    if rcon_send "quit"; then
        log "RCON quit command sent successfully"
    else
        log "RCON quit failed — falling back to direct SIGTERM"
    fi

    # 3) Wait for server to exit (up to 30s)
    if [[ $SERVER_PID -gt 0 ]]; then
        local timeout=30
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then
                log "Server process (PID $SERVER_PID) exited gracefully"
                exit 0
            fi
            sleep 1
            elapsed=$((elapsed + 1))
        done

        # 4) Force SIGTERM
        log "Server still alive after ${timeout}s — sending SIGTERM"
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        sleep 5

        # 5) Last resort: SIGKILL
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            log "Server still alive — sending SIGKILL"
            kill -KILL "$SERVER_PID" 2>/dev/null || true
        else
            log "Server exited after SIGTERM"
        fi
    fi

    exit 143  # 128 + 15 (SIGTERM)
}

trap shutdown_handler SIGTERM SIGINT

# --- Launch server ---
log "Changing to server directory: ${SERVER_DIR}"
cd "$SERVER_DIR"

if [[ "${USE_JAVA_FALLBACK,,}" == "true" ]]; then
    log "=== Java Fallback Mode ==="
    log "Launching Java directly (bypasses launcher)"

    # Background + wait preserves SIGTERM trap (unlike exec)
    # shellcheck disable=SC2086
    box64 java -Xmx"${XMX_VAL}" -Xms"${XMS_VAL}" \
        -Dzomboid.steam=1 \
        -Dzomboid.znetlog=1 \
        ${JAVA_EXTRA_ARGS:+$JAVA_EXTRA_ARGS} \
        -cp "${SERVER_DIR}/java/*:${SERVER_DIR}/ProjectZomboid64.jar" \
        zombie.network.Server \
        -cachedir /project-zomboid-config \
        -adminusername "${ADMIN_USERNAME:-admin}" \
        -adminpassword "${ADMIN_PASSWORD:-admin}" \
        -port 16261 &
    SERVER_PID=$!
    log "Java fallback PID: ${SERVER_PID}"
    # Non-blocking RCON readiness check in background
    ( wait_for_rcon_port 120 ) &

    wait "$SERVER_PID"
    WAIT_EXIT=$?
    log "Java fallback exited with code ${WAIT_EXIT}"
    exit ${WAIT_EXIT}
else
    log "=== Box64 Launcher Mode ==="
    log "Launching: box64 ${ZOMBOID64}"
    log "Server will listen on ports 8766/8767/16261-16262 (UDP) and ${RCON_PORT:-27015} (TCP)"

    # Run in background so signal trap works
    box64 "${ZOMBOID64}" &
    SERVER_PID=$!
    log "Server PID: ${SERVER_PID}"
    # Non-blocking RCON readiness check in background
    ( wait_for_rcon_port 120 ) &

    # Wait for server process — trap interrupts this on SIGTERM
    wait "$SERVER_PID"
    WAIT_EXIT=$?
    log "Server process exited with code ${WAIT_EXIT}"
    exit ${WAIT_EXIT}
fi

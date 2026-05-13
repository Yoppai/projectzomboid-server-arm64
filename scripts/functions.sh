#!/bin/bash
# Shared helper functions for Project Zomboid ARM64 server

# Log message with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Send RCON command to local server
# Usage: rcon_send "command"
rcon_send() {
    local cmd="$1"
    local rcon_host="127.0.0.1"
    local rcon_port="${RCON_PORT:-27015}"
    local rcon_pass="${RCON_PASSWORD:-changeme}"

    if ! command -v rcon &>/dev/null; then
        log "ERROR: rcon binary not found"
        return 1
    fi

    rcon -a "${rcon_host}:${rcon_port}" -p "${rcon_pass}" "${cmd}"
}

# Patch ProjectZomboid64.json with memory settings
# Usage: patch_memory_json [xmx_val] [xms_val]
patch_memory_json() {
    local server_json_path="/project-zomboid/ProjectZomboid64.json"
    local config_json_path="/project-zomboid-config/ProjectZomboid64.json"
    local json_path="$server_json_path"
    local xmx="${1:-${MEMORY:-2G}}"
    local xms="${2:-$xmx}"

    # ProjectZomboid64 reads the JSON beside the launcher binary, not the
    # config volume copy. Fall back to the config volume only before install.
    if [[ ! -f "$json_path" ]]; then
        json_path="$config_json_path"
    fi

    if [[ ! -f "$json_path" ]]; then
        log "WARNING: ${json_path} not found — creating default"
        mkdir -p "$(dirname "$json_path")"
        cat > "$json_path" <<EOF
{
  "vmArgs": "-Xmx${xmx} -Xms${xms}",
  "initialHeap": "${xms}",
  "maxHeap": "${xmx}"
}
EOF
        log "Created default memory config: -Xmx${xmx} -Xms${xms}"
        return 0
    fi

    if command -v jq &>/dev/null; then
        jq --arg xmx "${xmx}" --arg xms "${xms}" '
            def patch_vmargs:
                if (.vmArgs | type) == "array" then
                    .vmArgs |= (
                        map(select(. != "-XX:+UseZGC")) |
                        map(
                            if test("^-Xmx") then "-Xmx" + $xmx
                            elif test("^-Xms") then "-Xms" + $xms
                            else . end
                        ) |
                        (if any(test("^-Xmx")) then . else . + ["-Xmx" + $xmx] end) |
                        (if any(test("^-Xms")) then . else . + ["-Xms" + $xms] end)
                    )
                elif (.vmArgs | type) == "string" then
                    .vmArgs |= (
                        gsub("-XX:\\+UseZGC"; "") |
                        if test("-Xmx[0-9]+[kKmMgGtT]") then
                            gsub("-Xmx[0-9]+[kKmMgGtT]"; "-Xmx" + $xmx)
                        else
                            . + " -Xmx" + $xmx
                        end |
                        if test("-Xms[0-9]+[kKmMgGtT]") then
                            gsub("-Xms[0-9]+[kKmMgGtT]"; "-Xms" + $xms)
                        else
                            . + " -Xms" + $xms
                        end
                    )
                else
                    .vmArgs = ["-Xmx" + $xmx, "-Xms" + $xms]
                end;
            patch_vmargs | .initialHeap = $xms | .maxHeap = $xmx
        ' \
            "$json_path" > "${json_path}.tmp" && \
        mv "${json_path}.tmp" "$json_path"
        log "Patched memory config via jq (${json_path}): -Xmx${xmx} -Xms${xms}; removed -XX:+UseZGC for Box64"
    else
        log "WARNING: jq not available, using sed fallback"
        sed -i "s/-Xmx[0-9]*[kKmMgGtT]/-Xmx${xmx}/g; s/-Xms[0-9]*[kKmMgGtT]/-Xms${xms}/g" "$json_path" 2>/dev/null || \
        log "ERROR: Failed to patch memory config"
    fi
}

# Wait for RCON port to be ready
# Usage: wait_for_rcon_port [timeout_seconds]
wait_for_rcon_port() {
    local timeout="${1:-30}"
    local rcon_port="${RCON_PORT:-27015}"
    local elapsed=0

    log "Waiting for RCON port ${rcon_port}..."

    while [[ $elapsed -lt $timeout ]]; do
        if command -v nc &>/dev/null && nc -z 127.0.0.1 "${rcon_port}" 2>/dev/null; then
            log "RCON port ${rcon_port} is ready after ~${elapsed}s"
            return 0
        fi
        # Fallback check via /proc/net/tcp
        if [[ -r /proc/net/tcp ]]; then
            local hex_port
            hex_port=$(printf '%04X' "${rcon_port}" 2>/dev/null)
            if grep -qi "00000000:${hex_port}" /proc/net/tcp 2>/dev/null; then
                log "RCON port ${rcon_port} detected via /proc/net/tcp after ~${elapsed}s"
                return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log "WARNING: RCON port ${rcon_port} not ready after ${timeout}s"
    return 1
}

# -------------------------------------------------------------------
# PanelBridge mod installation
# -------------------------------------------------------------------
# Downloads PanelBridge mod files from a pinned GitHub source archive when enabled.
# Gracefully degrades on failure and disables bridge effects for the current run.
# -------------------------------------------------------------------
install_panelbridge() {
    export PANEL_BRIDGE_INSTALLED=false

    if [[ "${PANEL_BRIDGE_ENABLED,,}" != "true" ]]; then
        log "PanelBridge disabled — skipping download/install"
        return 0
    fi

    local version="${PANEL_BRIDGE_VERSION:-v1.0.26}"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "ERROR: PanelBridge version '$version' invalid; expected vX.Y.Z"
        export PANEL_BRIDGE_ENABLED=false
        return 1
    fi

    local source_url="${PANEL_BRIDGE_SOURCE_URL:-https://github.com/fpsacha/zomboid-control-panel/archive/refs/tags/${version}.tar.gz}"
    local checksum="${PANEL_BRIDGE_SHA256:-}"
    local project_zomboid_dir="${PROJECT_ZOMBOID_DIR:-/project-zomboid}"
    local target_dir="${project_zomboid_dir}/mods/PanelBridge"
    local parent_dir staging_dir backup_dir tmp_dir archive extract_dir source_dir

    if ! command -v curl &>/dev/null; then
        log "ERROR: curl not found; cannot download PanelBridge"
        export PANEL_BRIDGE_ENABLED=false
        return 1
    fi
    if [[ -n "$checksum" ]] && ! command -v sha256sum &>/dev/null; then
        log "ERROR: PANEL_BRIDGE_SHA256 set but sha256sum not found"
        export PANEL_BRIDGE_ENABLED=false
        return 1
    fi
    if ! command -v tar &>/dev/null; then
        log "ERROR: tar not found; cannot extract PanelBridge archive"
        export PANEL_BRIDGE_ENABLED=false
        return 1
    fi

    tmp_dir="$(mktemp -d)"
    archive="${tmp_dir}/panelbridge.tar.gz"
    extract_dir="${tmp_dir}/extract"
    mkdir -p "$extract_dir"

    _panelbridge_fail() {
        local message="$1"
        log "ERROR: ${message}; disabling PanelBridge for this run"
        export PANEL_BRIDGE_ENABLED=false
        export PANEL_BRIDGE_INSTALLED=false
        rm -rf "$tmp_dir"
        return 1
    }

    log "Downloading PanelBridge ${version} source archive"
    curl -fsSL --retry 3 --retry-delay 2 --max-time 60 \
        -o "$archive" \
        "$source_url" || { _panelbridge_fail "PanelBridge archive download failed"; return 1; }

    if [[ -n "$checksum" ]]; then
        printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - \
            || { _panelbridge_fail "PanelBridge archive checksum mismatch"; return 1; }
    fi

    tar -xzf "$archive" -C "$extract_dir" \
        || { _panelbridge_fail "PanelBridge archive extraction failed"; return 1; }

    source_dir="$(find "$extract_dir" -path '*/pz-mod/PanelBridge' -type d | head -n 1)"
    if [[ -z "$source_dir" ]]; then
        _panelbridge_fail "PanelBridge path pz-mod/PanelBridge not found in archive"
    fi
    if [[ ! -f "${source_dir}/mod.info" ]]; then
        _panelbridge_fail "PanelBridge mod.info missing in archive"
    fi
    if ! find "${source_dir}/media/lua/server" -maxdepth 1 -type f -name '*.lua' | grep -q .; then
        _panelbridge_fail "PanelBridge server Lua files missing in archive"
    fi

    parent_dir="$(dirname "$target_dir")"
    staging_dir="${parent_dir}/PanelBridge.tmp.$$"
    backup_dir="${parent_dir}/PanelBridge.old.$$"
    mkdir -p "$parent_dir"
    rm -rf "$staging_dir" "$backup_dir"
    cp -a "$source_dir" "$staging_dir" \
        || { _panelbridge_fail "PanelBridge staging copy failed"; return 1; }

    if [[ -d "$target_dir" ]]; then
        mv "$target_dir" "$backup_dir" \
            || { _panelbridge_fail "PanelBridge existing install backup failed"; return 1; }
    fi
    mv "$staging_dir" "$target_dir" \
        || {
            [[ -d "$backup_dir" ]] && mv "$backup_dir" "$target_dir" 2>/dev/null || true
            _panelbridge_fail "PanelBridge atomic install failed"
        }

    rm -rf "$backup_dir" "$tmp_dir"

    export PANEL_BRIDGE_INSTALLED=true
    log "PanelBridge ${version} installed from pinned source archive"
}

# -------------------------------------------------------------------
# Env-to-INI mapping
# -------------------------------------------------------------------
# Returns lines of: INI_KEY=ENV_VAR_NAME
# Ordered for readability. Anti-cheat entries are generated separately.
# -------------------------------------------------------------------
env_to_ini_map() {
    # === Network / Ports ===
    cat <<ENVTOINI
DefaultPort=DEFAULT_PORT
UDPPort=UDP_PORT
RCONPort=RCON_PORT
RCONPassword=RCON_PASSWORD
Password=PASSWORD

# === Admin / Auth ===
AdminUsername=ADMIN_USERNAME
AdminPassword=ADMIN_PASSWORD
AutoCreateUserInWhiteList=AUTO_CREATE_USER_IN_WHITE_LIST
DisplayUserName=DISPLAY_USER_NAME
ShowFirstAndLastName=SHOW_FIRST_AND_LAST_NAME

# === Server Identity ===
Public=SERVER_PUBLIC
PublicName=PUBLIC_NAME
PublicDescription=PUBLIC_DESCRIPTION
ServerWelcomeMessage=SERVER_WELCOME_MESSAGE
ServerPlayerID=SERVER_PLAYER_ID
ResetID=RESET_ID

# === Gameplay Toggles ===
PVP=PVP
PauseEmpty=PAUSE_EMPTY
GlobalChat=GLOBAL_CHAT
Open=OPEN
SafetySystem=SAFETY_SYSTEM
ShowSafety=SHOW_SAFETY
SafetyToggleTimer=SAFETY_TOGGLE_TIMER
SafetyCooldownTimer=SAFETY_COOLDOWN_TIMER
DoLuaChecksum=DO_LUA_CHECKSUM
DenyLoginOnOverloadedServer=DENY_LOGIN_ON_OVERLOADED_SERVER
NoFire=NO_FIRE
AnnounceDeath=ANNOUNCE_DEATH
AllowDestructionBySledgehammer=ALLOW_DESTRUCTION_BY_SLEDGEHAMMER
SledgehammerOnlyInSafehouse=SLEDGEHAMMER_ONLY_IN_SAFEHOUSE
KickFastPlayers=KICK_FAST_PLAYERS
AllowCoop=ALLOW_COOP
SleepAllowed=SLEEP_ALLOWED
SleepNeeded=SLEEP_NEEDED
KnockedDownAllowed=KNOCKED_DOWN_ALLOWED
SneakModeHideFromOtherPlayers=SNEAK_MODE_HIDE_FROM_OTHER_PLAYERS
SteamScoreboard=STEAM_SCOREBOARD
SteamVAC=STEAM_VAC
UPnP=UPNP
VoiceEnable=VOICE_ENABLE
Voice3D=VOICE_3D
Faction=FACTION
DisableRadioStaff=DISABLE_RADIO_STAFF
DisableRadioAdmin=DISABLE_RADIO_ADMIN
DisableRadioGM=DISABLE_RADIO_GM
DisableRadioOverseer=DISABLE_RADIO_OVERSEER
DisableRadioModerator=DISABLE_RADIO_MODERATOR
DisableRadioInvisible=DISABLE_RADIO_INVISIBLE
BanKickGlobalSound=BAN_KICK_GLOBAL_SOUND
RemovePlayerCorpsesOnCorpseRemoval=REMOVE_PLAYER_CORPSES_ON_CORPSE_REMOVAL
TrashDeleteAll=TRASH_DELETE_ALL
PVPMeleeWhileHitReaction=PVP_MELEE_WHILE_HIT_REACTION
MouseOverToSeeDisplayName=MOUSE_OVER_TO_SEE_DISPLAY_NAME
HidePlayersBehindYou=HIDE_PLAYERS_BEHIND_YOU
PlayerBumpPlayer=PLAYER_BUMP_PLAYER
AllowNonAsciiUsername=ALLOW_NON_ASCII_USERNAME
DiscordEnable=DISCORD_ENABLE
LoginQueueEnabled=LOGIN_QUEUE_ENABLED
PlayerRespawnWithSelf=PLAYER_RESPAWN_WITH_SELF
PlayerRespawnWithOther=PLAYER_RESPAWN_WITH_OTHER
DisableSafehouseWhenPlayerConnected=DISABLE_SAFEHOUSE_WHEN_PLAYER_CONNECTED

# === Numeric Tuning ===
MaxPlayers=MAX_PLAYERS
PingLimit=PING_LIMIT
HoursForLootRespawn=HOURS_FOR_LOOT_RESPAWN
MaxItemsForLootRespawn=MAX_ITEMS_FOR_LOOT_RESPAWN
ConstructionPreventsLootRespawn=CONSTRUCTION_PREVENTS_LOOT_RESPAWN
DropOffWhiteListAfterDeath=DROP_OFF_WHITE_LIST_AFTER_DEATH
MinutesPerPage=MINUTES_PER_PAGE
SaveWorldEveryMinutes=SAVE_WORLD_EVERY_MINUTES
SafehouseRemovalTime=SAFEHOUSE_REMOVAL_TIME
SafehouseDaySurvivedToClaim=SAFEHOUSE_DAY_SURVIVED_TO_CLAIM
VoiceMinDistance=VOICE_MIN_DISTANCE
VoiceMaxDistance=VOICE_MAX_DISTANCE
SpeedLimit=SPEED_LIMIT
FastForwardMultiplier=FAST_FORWARD_MULTIPLIER
FactionDaySurvivedToCreate=FACTION_DAY_SURVIVED_TO_CREATE
FactionPlayersRequiredForTag=FACTION_PLAYERS_REQUIRED_FOR_TAG
ItemNumbersLimitPerContainer=ITEM_NUMBERS_LIMIT_PER_CONTAINER
BloodSplatLifespanDays=BLOOD_SPLAT_LIFESPAN_DAYS
LoginQueueConnectTimeout=LOGIN_QUEUE_CONNECT_TIMEOUT
PVPMeleeDamageModifier=PVP_MELEE_DAMAGE_MODIFIER
PVPFirearmDamageModifier=PVP_FIREARM_DAMAGE_MODIFIER
CarEngineAttractionModifier=CAR_ENGINE_ATTRACTION_MODIFIER
MapRemotePlayerVisibility=MAP_REMOTE_PLAYER_VISIBILITY
BackupsCount=BACKUPS_COUNT
BackupsPeriod=BACKUPS_PERIOD
BackupsOnStart=BACKUPS_ON_START
BackupsOnVersionChange=BACKUPS_ON_VERSION_CHANGE
MaxAccountsPerUser=MAX_ACCOUNTS_PER_USER

# === Safehouse ===
PlayerSafehouse=PLAYER_SAFEHOUSE
AdminSafehouse=ADMIN_SAFEHOUSE
SafehouseAllowTrespass=SAFEHOUSE_ALLOW_TRESPASS
SafehouseAllowFire=SAFEHOUSE_ALLOW_FIRE
SafehouseAllowLoot=SAFEHOUSE_ALLOW_LOOT
SafehouseAllowRespawn=SAFEHOUSE_ALLOW_RESPAWN
SafehouseAllowNonResidential=SAFEHOUSE_ALLOW_NON_RESIDENTIAL

# === Text / Chat ===
ChatStreams=CHAT_STREAMS
ClientCommandFilter=CLIENT_COMMAND_FILTER
ClientActionLogs=CLIENT_ACTION_LOGS
PerkLogs=PERK_LOGS

# === Misc ===
SpawnPoint=SPAWN_POINT
SpawnItems=SPAWN_ITEMS
Map=MAP
ServerBrowserAnnouncedIP=SERVER_BROWSER_ANNOUNCED_IP
DiscordToken=DISCORD_TOKEN
DiscordChannel=DISCORD_CHANNEL
DiscordChannelID=DISCORD_CHANNEL_ID
ENVTOINI
}

# Generate anti-cheat env-to-ini mappings dynamically
# Outputs lines of: INI_KEY=ENV_VAR_NAME
env_to_ini_anticheat_map() {
    local type_num
    # Types 1-24 with explicit true/false toggle
    for type_num in $(seq 1 24); do
        echo "AntiCheatProtectionType${type_num}=ANTI_CHEAT_PROTECTION_TYPE${type_num}"
    done
    # Threshold multipliers: 2,3,4,9,15,20,22,24
    for type_num in 2 3 4 9 15 20 22 24; do
        echo "AntiCheatProtectionType${type_num}Threshold=ANTI_CHEAT_PROTECTION_TYPE${type_num}_THRESHOLD_MULTIPLIER"
    done
}

# -------------------------------------------------------------------
# Env-to-INI config patching
# -------------------------------------------------------------------
# When GENERATE_SETTINGS=true: idempotently patches known env vars
#   into CONFIG_DIR/Server/${SERVER_NAME}.ini.
# When false: skips entirely to preserve user edits.
#
# Admin/RCON settings are ALWAYS written (even when GENERATE_SETTINGS=false)
# because server won't start without them.
# -------------------------------------------------------------------
patch_server_ini() {
    local server_name="${SERVER_NAME:-pzserver}"
    local config_dir="${CONFIG_DIR:-/project-zomboid-config}"
    local ini_path="${config_dir}/Server/${server_name}.ini"
    local generate="${GENERATE_SETTINGS:-true}"

    # --- Always: ensure admin/RCON basics exist for server start ---
    mkdir -p "$(dirname "$ini_path")"

    if [[ ! -f "$ini_path" ]]; then
        # Create minimal INI with required fields
        cat > "$ini_path" <<-INI
DefaultPort=${DEFAULT_PORT:-16261}
UDPPort=${UDP_PORT:-16262}
Password=${PASSWORD:-}
Public=${SERVER_PUBLIC:-${PUBLIC:-false}}
PublicName=${PUBLIC_NAME:-Project Zomboid Server}
RCONPort=${RCON_PORT:-27015}
RCONPassword=${RCON_PASSWORD:-changeme}
AdminUsername=${ADMIN_USERNAME:-admin}
AdminPassword=${ADMIN_PASSWORD:-admin}
INI
        log "Created ${ini_path} with default values"
    fi

    # --- GENERATE_SETTINGS gate ---
    if [[ "${generate,,}" != "true" ]]; then
        log "GENERATE_SETTINGS=false — skipping env-to-ini patching for server settings"
        log "Admin/RCON settings remain from initial file creation"
        return 0
    fi

    log "GENERATE_SETTINGS=true — applying env vars to ${ini_path}"

    # --- Full env-to-ini patching ---
    local tmp_ini
    tmp_ini="$(mktemp)"
    cp "$ini_path" "$tmp_ini"

    # Helper: set a key=value in the temp ini (update or append)
    _ini_set_key() {
        local key="$1"
        local val="$2"
        # Escape sed special chars in val: /, \, &
        local val_escaped
        val_escaped=$(printf '%s\n' "$val" | sed 's/[\/&]/\\&/g; s/$/\\n/' | tr -d '\n')
        if grep -qi "^${key}=" "$tmp_ini" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${val_escaped}|I" "$tmp_ini"
        else
            echo "${key}=${val}" >> "$tmp_ini"
        fi
    }

    # 1) Process explicit env_to_ini_map entries
    while IFS='=' read -r ini_key env_name; do
        # Skip comment lines and blank lines
        [[ -z "$ini_key" || "$ini_key" == \#* ]] && continue
        # Safe indirect expansion: read env var value if set
        local val
        val="${!env_name-}"
        # Alias fallback: if primary var is unset, check alias
        if [[ -z "$val" ]]; then
            case "$env_name" in
                SERVER_PUBLIC) val="${PUBLIC-}" ;;
            esac
        fi
        _ini_set_key "$ini_key" "$val"
    done < <(env_to_ini_map)

    local panelbridge_active=false
    local project_zomboid_dir="${PROJECT_ZOMBOID_DIR:-/project-zomboid}"
    if [[ "${PANEL_BRIDGE_ENABLED,,}" == "true" && "${PANEL_BRIDGE_INSTALLED,,}" == "true" && -f "${project_zomboid_dir}/mods/PanelBridge/mod.info" ]]; then
        panelbridge_active=true
    fi

    # PanelBridge: force DoLuaChecksum=false only when install succeeded and is active
    if [[ "$panelbridge_active" == "true" ]]; then
        _ini_set_key "DoLuaChecksum" "false"
    fi

    # 2) Process anti-cheat entries
    while IFS='=' read -r ini_key env_name; do
        local val="${!env_name-}"
        # Support _THRESHOLD alias for _THRESHOLD_MULTIPLIER
        if [[ -z "$val" && "$env_name" == *_THRESHOLD_MULTIPLIER ]]; then
            local alias_name="${env_name%_THRESHOLD_MULTIPLIER}_THRESHOLD"
            val="${!alias_name-}"
        fi
        _ini_set_key "$ini_key" "$val"
    done < <(env_to_ini_anticheat_map)

    # 3) Mods and WorkshopItems — special handling
    #    PanelBridge appended automatically when enabled (deduplicated)
    #    PanelBridge removed from INI when disabled (rollback)
    #    Box64 native-library warning suppressed when Mods is only PanelBridge
    local mods_val="${MODS-}"
    if [[ "$panelbridge_active" == "true" ]]; then
        if [[ -n "$mods_val" ]]; then
            [[ ";${mods_val};" != *";PanelBridge;"* ]] && mods_val="${mods_val};PanelBridge"
        else
            mods_val="PanelBridge"
        fi
    else
        # Rollback: remove PanelBridge from MODS when PB is disabled
        # Only clean INI if user did NOT set MODS explicitly (mods_val is empty)
        # If user set MODS, their value is authoritative (already validated no PanelBridge)
        if [[ -z "$mods_val" ]]; then
            local current_mods
            current_mods=$(grep -i '^Mods=' "$tmp_ini" 2>/dev/null | head -1 | cut -d= -f2-)
            if [[ -n "$current_mods" ]]; then
                # Remove PanelBridge from semicolon-separated list
                local cleaned=""
                local IFS_save="$IFS"
                IFS=';'
                for m in $current_mods; do
                    [[ -z "$m" ]] && continue
                    [[ "$m" == "PanelBridge" ]] && continue
                    cleaned="${cleaned}${cleaned:+;}${m}"
                done
                IFS="$IFS_save"
                if [[ "$cleaned" != "$current_mods" ]]; then
                    if [[ -n "$cleaned" ]]; then
                        mods_val="$cleaned"
                        log "INFO: PanelBridge removed from Mods (rollback)"
                    else
                        # Mods was only PanelBridge — remove the key entirely
                        sed -i '/^Mods=/Id' "$tmp_ini"
                        log "INFO: PanelBridge-only Mods removed (rollback)"
                    fi
                fi
            fi
        fi
    fi
    if [[ -n "$mods_val" ]]; then
        if [[ "$mods_val" == "PanelBridge" ]]; then
            log "INFO: PanelBridge (Lua-only) enabled"
        else
            log "WARNING: Mods with native libs may crash under Box64 — Mods=${mods_val}"
        fi
        _ini_set_key "Mods" "$mods_val"
    fi

    local ws_val="${WORKSHOP_ITEMS-}"
    if [[ -n "$ws_val" ]]; then
        _ini_set_key "WorkshopItems" "$ws_val"
    fi

    # 4) Backup toggle vars that need to be written as booleans consistently
    #    (already handled by env_to_ini_map above)

    mv "$tmp_ini" "$ini_path"
    log "Settings applied to ${ini_path}"
}

# -------------------------------------------------------------------
# Memory resolution helper
# -------------------------------------------------------------------
# Resolves JVM heap settings from env vars.
# Priority: MEMORY_XMX_GB → legacy MEMORY
# MEMORY_XMS_GB is optional; defaults to XMX value.
# -------------------------------------------------------------------
resolve_memory() {
    local xmx xms

    if [[ -n "${MEMORY_XMX_GB:-}" ]]; then
        xmx="${MEMORY_XMX_GB}G"
        if [[ -n "${MEMORY_XMS_GB:-}" ]]; then
            xms="${MEMORY_XMS_GB}G"
        else
            xms="$xmx"
        fi
    else
        # Fallback to legacy MEMORY
        xmx="${MEMORY:-2G}"
        xms="$xmx"
    fi

    echo "$xmx $xms"
}

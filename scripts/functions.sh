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
    local json_path="/project-zomboid-config/ProjectZomboid64.json"
    local xmx="${1:-${MEMORY:-2G}}"
    local xms="${2:-$xmx}"

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
        jq --arg xmx "${xmx}" --arg xms "${xms}" \
           '.vmArgs = "-Xmx" + $xmx + " -Xms" + $xms | .initialHeap = $xms | .maxHeap = $xmx' \
           "$json_path" > "${json_path}.tmp" && \
        mv "${json_path}.tmp" "$json_path"
        log "Patched memory config via jq: -Xmx${xmx} -Xms${xms}"
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

    # 3) Mods and WorkshopItems — special handling: only write if non-empty,
    #    log a warning when mods are enabled
    local mods_val="${MODS-}"
    if [[ -n "$mods_val" ]]; then
        log "WARNING: Mods enabled via env — Mods=${mods_val}"
        log "  Mods with native x86_64 libraries may crash under Box64"
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

# Environment Variables Reference

Complete reference of all environment variables supported by the Project Zomboid ARM64 Docker image. Variables are mapped to `Server/<SERVER_NAME>.ini` keys at container start via `functions.sh`.

---

## [User] File Ownership

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User ID for volume file ownership |
| `PGID` | `1000` | Group ID for volume file ownership |

---

## [Memory] JVM Heap Sizing

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_XMX_GB` | `8` | Max heap in GB (preferred). Overrides `MEMORY`. |
| `MEMORY_XMS_GB` | *(empty)* | Initial heap in GB (optional; defaults to XMX value) |
| `MEMORY` | `2G` | Legacy fallback when `MEMORY_XMX_GB` unset (e.g. `4G`, `8192M`) |

Priority: `MEMORY_XMX_GB` -> `MEMORY` -> default `2G`.

---

## [Important] Must Change

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSWORD` | `CHANGEME` | Server join password (leave blank for open) |
| `RCON_PASSWORD` | `changeme` | RCON admin password |
| `ADMIN_USERNAME` | `admin` | Server admin username |
| `ADMIN_PASSWORD` | `admin` | Server admin password |

---

## [Mod] Workshop

| Variable | Default | Description |
|----------|---------|-------------|
| `MODS` | *(empty)* | Semicolon-separated mod IDs |
| `WORKSHOP_ITEMS` | *(empty)* | Semicolon-separated workshop item IDs |

---

## [Mod] PanelBridge (Zomboid Control Panel)

| Variable | Default | Description |
|----------|---------|-------------|
| `PANEL_BRIDGE_ENABLED` | `false` | Download and install PanelBridge mod from GitHub at container start |
| `PANEL_BRIDGE_VERSION` | `v1.0.26` | PanelBridge release tag on GitHub (semver `vX.Y.Z`) |

When `PANEL_BRIDGE_ENABLED=true`, the container automatically:
1. Downloads `mod.info` and `PanelBridge.lua` from the tagged GitHub release
2. Places them in `/project-zomboid/mods/PanelBridge/`
3. Forces `DoLuaChecksum=false` in server INI (required by PanelBridge)
4. Appends `PanelBridge` to `Mods` in server INI

Set `PANEL_BRIDGE_ENABLED=false` to rollback -- next container start cleans PanelBridge from INI automatically.

Connect the control panel: Run the panel separately (another container, another machine). Point it to the server's RCON port (`27015` by default) with the `RCON_PASSWORD`. The panel handles the rest.

---

## [Server] Gameplay Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | `pzserver` | Server name (used as INI filename: `Server/<name>.ini`) |
| `SERVER_PUBLIC` | `true` | Public listing on Steam server browser. Use `PUBLIC` as backwards-compatible alias for direct Docker run. |
| `PUBLIC_NAME` | `Project Zomboid Server` | Display name in server browser |
| `PUBLIC_DESCRIPTION` | *(see .env.example)* | Server description |
| `SERVER_WELCOME_MESSAGE` | *(see .env.example)* | Join message |
| `SERVER_BROWSER_ANNOUNCED_IP` | *(empty)* | Override public IP for server browser |
| `DEFAULT_PORT` | `16261` | Primary game port |
| `UDP_PORT` | `16262` | Secondary UDP port |
| `RCON_PORT` | `27015` | RCON TCP port |
| `MAX_PLAYERS` | `32` | Max concurrent players |
| `PING_LIMIT` | `400` | Max ping before kick |
| `PVP` | `true` | Enable player-vs-player |
| `PAUSE_EMPTY` | `true` | Pause when no players online |
| `GLOBAL_CHAT` | `true` | Enable global chat |
| `OPEN` | `true` | Allow public connections |
| `SAFETY_SYSTEM` | `true` | Enable safezone system |
| `DO_LUA_CHECKSUM` | `true` | Verify Lua checksum on join |
| `STEAM_VAC` | `true` | Enable Steam VAC |
| `UPNP` | `true` | Enable UPnP port forwarding |
| `VOICE_ENABLE` | `true` | Enable voice chat |
| `FACTION` | `true` | Enable factions |
| `ALLOW_DESTRUCTION_BY_SLEDGEHAMMER` | `true` | Allow sledgehammer destruction |
| `HOURS_FOR_LOOT_RESPAWN` | `0` | Hours between loot respawn (0=never) |
| `SAVE_WORLD_EVERY_MINUTES` | `0` | Auto-save interval (0=use default) |
| `BACKUPS_COUNT` | `5` | Number of backup saves to retain |
| `BACKUPS_ON_START` | `true` | Run save backup on each server start |
| `BACKUPS_ON_VERSION_CHANGE` | `true` | Run save backup on version change |

Plus 70+ additional settings. See `.env.example` for full list.

---

## [Anti-Cheat] Protection

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTI_CHEAT_PROTECTION_TYPE1` .. `TYPE24` | `true` | Enable/disable each anti-cheat check |
| `ANTI_CHEAT_PROTECTION_TYPE{N}_THRESHOLD_MULTIPLIER` | *(varies)* | Sensitivity threshold for select types (2,3,4,9,15,20,22,24). `_THRESHOLD` suffix is a shorter alias (e.g., `ANTI_CHEAT_PROTECTION_TYPE2_THRESHOLD`). |

---

## [ARM] ARM64-Specific Extras

| Variable | Default | Description |
|----------|---------|-------------|
| `BRANCH` | *(empty)* | Steam beta branch passed to SteamCMD (`-beta <branch>`). See [Server Branches](configuration.md#server-branches). |
| `SERVER_BRANCH` | *(empty)* | Backwards-compatible alias for `BRANCH` |
| `UPDATE_ON_START` | `true` | Run SteamCMD update on each container start |
| `DISABLE_STEAM` | `false` | Skip SteamCMD entirely |
| `GENERATE_SETTINGS` | `true` | When true, patches `Server/<SERVER_NAME>.ini` from env vars. Set false to preserve user edits. |
| `USE_JAVA_FALLBACK` | `false` | Bypass Box64 launcher, invoke Java directly |
| `JAVA_EXTRA_ARGS` | *(empty)* | Extra JVM flags (e.g. `-XX:+UseZGC`) |
| `ARM64_DEVICE` | *(empty)* | Informational: set to device model for future Box64 tuning |
| `BOX64_DYNAREC_BIGBLOCK` | `1` | Box64 big block optimization (set `0` if crashes) |
| `BOX64_DYNAREC_BLEEDING_EDGE` | `0` | Experimental optimizations |
| `BOX64_DYNAREC_BB_LOOP` | `1` | Basic block loop optimization |
| `BOX64_DYNAREC_FORWARD` | `1` | Forward jump optimization |
| `BOX64_DYNAREC_STRONGMEM` | `1` | Strong memory ordering emulation |

---

## Env-to-INI Mapping

The `env_to_ini_map()` function in `functions.sh` defines the mapping between environment variables and `server.ini` keys:

| Env Var | INI Key |
|---------|---------|
| `PASSWORD` | `Password` |
| `RCON_PASSWORD` | `RCONPassword` |
| `RCON_PORT` | `RCONPort` |
| `MODS` | `Mods` |
| `WORKSHOP_ITEMS` | `WorkshopItems` |
| `PVP` | `PVP` |
| `PAUSE_EMPTY` | `PauseEmpty` |
| `DEFAULT_PORT` | `DefaultPort` |
| `SERVER_PUBLIC` | `Public` |
| `ANTI_CHEAT_PROTECTION_TYPE2` | `AntiCheatProtectionType2` |
| `ANTI_CHEAT_PROTECTION_TYPE2_THRESHOLD_MULTIPLIER` | `AntiCheatProtectionType2Threshold` |
| `CONSTRUCTION_PREVENTS_LOOT_RESPAWN` | `ConstructionPreventsLootRespawn` |
| `DROP_OFF_WHITE_LIST_AFTER_DEATH` | `DropOffWhiteListAfterDeath` |
| `BACKUPS_ON_START` | `BackupsOnStart` |
| `BACKUPS_ON_VERSION_CHANGE` | `BackupsOnVersionChange` |
| *90+ total mappings* | |

Anti-cheat vars follow a pattern: `ANTI_CHEAT_PROTECTION_TYPE{N}` -> `AntiCheatProtectionType{N}`, with `_THRESHOLD_MULTIPLIER` suffix -> `Threshold` (PascalCase). The `_THRESHOLD` suffix is accepted as an alias for `_THRESHOLD_MULTIPLIER` -- both through compose env and direct script fallback.

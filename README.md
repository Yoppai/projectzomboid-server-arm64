# Project Zomboid Dedicated Server — ARM64

Multi-stage Docker image for running Project Zomboid dedicated server on **ARM64** (Oracle Cloud A1 Flex, Raspberry Pi, Apple Silicon, AWS Graviton, etc.).

The x86_64 server binary runs under [Box64](https://github.com/ptitSeb/box64) dynarec emulation on a `steamcmd-arm64` base image. No native ARM64 Project Zomboid binary exists.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Stage 1: rcon-builder (golang:1.22-bookworm)              │
│  └─ GOOS=linux GOARCH=arm64 → gorcon/rcon-cli binary       │
├────────────────────────────────────────────────────────────┤
│  Stage 2: final (sonroyaalmerol/steamcmd-arm64:root-bookworm) │
│  ├─ gosu jq nc                                             │
│  ├─ rcon from Stage 1                                      │
│  ├─ init.sh (entrypoint) → env validation + user setup     │
│  ├─ install.scmd → SteamCMD app 380870 update              │
│  ├─ start-arm64.sh → Box64 → ProjectZomboid64             │
│  └─ validate.sh → lightweight syntax checks                │
└────────────────────────────────────────────────────────────┘
```

### Scripts

| Script | Role |
|--------|------|
| `init.sh` | Entrypoint — validate env, create user, fix perms, run install, gosu to start |
| `functions.sh` | Shared helpers — `log`, `rcon_send`, `patch_memory_json`, `patch_server_ini` (env-to-INI mapping), `wait_for_rcon_port`, `resolve_memory` |
| `install.scmd` | SteamCMD install/update app 380870 with branch support |
| `install_version.scmd` | Helper for manual branch-specific install |
| `start-arm64.sh` | Box64 env setup, memory patching, signal trap, server launch |
| `validate.sh` | Lightweight syntax checks (bash -n, optional shellcheck, docker compose config) |

## Quick Start

### Prerequisites

- Docker with `buildx` plugin (for ARM64 cross-platform builds)
- ARM64 host (or QEMU emulation for testing on amd64)

### Build

```bash
# Build for ARM64
docker buildx build --platform linux/arm64 -t pz-arm64 .
```

### Run with Docker Compose

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env — set MEMORY_XMX_GB, PASSWORD, RCON_PASSWORD, PUID, PGID

# 2. Start server
docker compose up -d

# 3. Watch logs
docker compose logs -f

# 4. Stop gracefully
docker compose stop
```

### Run with Docker directly

```bash
docker run -d \
  --name pz-server \
  --platform linux/arm64 \
  -e MEMORY_XMX_GB=8 \
  -e PASSWORD=CHANGEME \
  -e RCON_PASSWORD=changeme \
  -e PUID=1000 \
  -e PGID=1000 \
  -p 8766:8766/udp \
  -p 8767:8767/udp \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  -p 27015:27015/tcp \
  -v pz-data:/project-zomboid \
  -v pz-config:/project-zomboid-config \
  pz-arm64
```

## Environment Variables

### [User] File Ownership

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User ID for volume file ownership |
| `PGID` | `1000` | Group ID for volume file ownership |

### [Memory] JVM Heap Sizing

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_XMX_GB` | `8` | Max heap in GB (preferred). Overrides `MEMORY`. |
| `MEMORY_XMS_GB` | *(empty)* | Initial heap in GB (optional; defaults to XMX value) |
| `MEMORY` | `2G` | Legacy fallback when `MEMORY_XMX_GB` unset (e.g. `4G`, `8192M`) |

Priority: `MEMORY_XMX_GB` → `MEMORY` → default `2G`.

### [Important] Must Change

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSWORD` | `CHANGEME` | Server join password (leave blank for open) |
| `RCON_PASSWORD` | `changeme` | RCON admin password |
| `ADMIN_USERNAME` | `admin` | Server admin username |
| `ADMIN_PASSWORD` | `admin` | Server admin password |

### [Mod] Workshop

| Variable | Default | Description |
|----------|---------|-------------|
| `MODS` | *(empty)* | Semicolon-separated mod IDs |
| `WORKSHOP_ITEMS` | *(empty)* | Semicolon-separated workshop item IDs |

### [Server] Gameplay Settings

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
| *Plus 70+ additional settings* | | See `.env.example` for full list |

### [Anti-Cheat] Protection

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTI_CHEAT_PROTECTION_TYPE1` … `TYPE24` | `true` | Enable/disable each anti-cheat check |
| `ANTI_CHEAT_PROTECTION_TYPE{N}_THRESHOLD_MULTIPLIER` | *(varies)* | Sensitivity threshold for select types (2,3,4,9,15,20,22,24). `_THRESHOLD` suffix is a shorter alias (e.g., `ANTI_CHEAT_PROTECTION_TYPE2_THRESHOLD`). |

### [ARM] ARM64-Specific Extras

| Variable | Default | Description |
|----------|---------|-------------|
| `BRANCH` | *(empty)* | Steam beta branch (e.g. `b41multiplayer`, `b42test`). |
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

## Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `pz-data` | `/project-zomboid` | Server saves, mods, logs |
| `pz-config` | `/project-zomboid-config` | `ProjectZomboid64.json`, server INIs (`Server/*.ini`) |
| `pz-steamapps` | `/steamapps` | SteamCMD download cache |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8766 | UDP | Game traffic |
| 8767 | UDP | Game traffic |
| 16261 | UDP | Steam query / master server (`DEFAULT_PORT`) |
| 16262 | UDP | Secondary game port (`UDP_PORT`) |
| 27015 | TCP | RCON (configurable via `RCON_PORT`) |

## Config Generation

The server configuration lives in `Server/<SERVER_NAME>.ini` inside the config volume.

- **`GENERATE_SETTINGS=true`** (default): On each start, env vars are mapped idempotently to INI keys. Unknown keys and comments are preserved. This is the recommended setting for initial setup and containerized deployments where config is managed through env vars.

- **`GENERATE_SETTINGS=false`**: The INI file is never touched except for minimal required fields (admin credentials, RCON, ports) when the file is first created. Use this to make manual edits to the INI file and have them persist across restarts.

### Env-to-INI Mapping

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
| *… 90+ total mappings* | |

Anti-cheat vars follow a pattern: `ANTI_CHEAT_PROTECTION_TYPE{N}` → `AntiCheatProtectionType{N}`, with `_THRESHOLD_MULTIPLIER` suffix → `Threshold` (PascalCase). The `_THRESHOLD` suffix is accepted as an alias for `_THRESHOLD_MULTIPLIER` — both through compose env and direct script fallback.

## Box64 Tuning

Box64 emulates the x86_64 Project Zomboid binary on ARM64. Key tuning knobs:

| Variable | Default | Effect |
|----------|---------|--------|
| `BOX64_DYNAREC_BIGBLOCK=0` | `1` | Disable big block optimization (more stable, slightly slower) |
| `BOX64_DYNAREC_BLEEDING_EDGE=1` | `0` | Enable bleeding edge optimizations (faster, less stable) |
| `BOX64_DYNAREC_FORWARD=0` | `1` | Disable forward jump optimization |
| `BOX64_DYNAREC_STRONGMEM=0` | `1` | Disable strong memory ordering (may improve perf on some ARM CPUs) |

If the server crashes on startup, try:
```bash
BOX64_DYNAREC_BIGBLOCK=0 BOX64_DYNAREC_BLEEDING_EDGE=0
```

## Java Fallback Mode

Set `USE_JAVA_FALLBACK=true` if the Box64 launcher (`ProjectZomboid64`) becomes incompatible (e.g., after a game update). This bypasses the launcher and invokes Java directly:

```bash
docker run -e USE_JAVA_FALLBACK=true ...
```

Additional JVM flags can be passed via `JAVA_EXTRA_ARGS`. Note: Classpath may need adjustment for Build 42 changes. Check game logs if fallback fails.

## Graceful Shutdown

The container handles `SIGTERM` in this order:

1. Send `quit` via RCON
2. Wait 30s for server to exit
3. Send `SIGTERM` to server PID
4. Wait 5s
5. Send `SIGKILL` as last resort

The `stop_grace_period` in `docker-compose.yml` is set to `90s` to accommodate the full shutdown sequence.

## Validation

### Local syntax checks (no Docker build required)

```bash
# Full validation suite
./scripts/validate.sh

# Or run individual checks:
bash -n scripts/*.sh scripts/*.scmd
docker compose config
shellcheck scripts/*.sh scripts/*.scmd   # if installed
```

### Build validation

```bash
# Shellcheck all scripts
shellcheck scripts/*.sh scripts/*.scmd

# Verify Dockerfile syntax + build
docker buildx build --platform linux/arm64 -t pz-arm64 .
```

### Binary validation

```bash
# Check rcon binary architecture
docker run --rm --platform linux/arm64 pz-arm64 file /usr/local/bin/rcon
# Expected: ELF 64-bit LSB executable, ARM aarch64
```

### Runtime validation

```bash
# Start with compose
docker compose up

# Expected log sequence:
# 1. Box64 env vars exported
# 2. SteamCMD app_update 380870
# 3. Server listening on ports

# Test graceful shutdown
docker stop --time 90 <container_name>

# Check RCON quit in logs:
# [RCON] quit command received → server exits cleanly
```

### Volume ownership validation

```bash
# Check mounted volume ownership matches PUID/PGID
docker run --rm -v pz-data:/data alpine ls -ln /data
```

## Build 42 Compatibility

| Risk | Mitigation |
|------|------------|
| Launcher renamed | Set `USE_JAVA_FALLBACK=true` |
| JSON schema changes | `JAVA_EXTRA_ARGS` appends custom flags; jq logs warning |
| Box64 dynarec crash | Set `BOX64_DYNAREC_BIGBLOCK=0` |
| 32-bit helper required | Base image includes Box32; `BOX86_*` vars auto-honored |
| Mod native libs break | Set `GENERATE_SETTINGS=true`, test mods individually, use `GENERATE_SETTINGS=false` to lock known-good config |

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Shell script bugs (quoting, globbing) | Med | Run `./scripts/validate.sh` before merge; scripts use `set -e` + safe indirect expansion |
| ARM hardware incompatibility (Pi 3, old kernels) | Low | Recommended: Raspberry Pi 4/5, Apple Silicon M1+, AWS Graviton2+. Pi 3 may struggle with RAM limits |
| Box64 base image drift / regression | Low | Pin image tag; test new images in staging |
| Config overwrite on restart | Med | Set `GENERATE_SETTINGS=false` after initial setup to preserve manual INI edits |
| Env-to-INI key drift on game updates | Med | `env_to_ini_map()` must be updated when PZ adds/removes INI keys; validate.sh checks for orphaned vars |
| Mod native x86_64 libs crash Box64 | Med | Log warning when `MODS` non-empty; test mods individually |
| RCON password in compose env | Low | Use `.env` file (excluded from Docker build context) instead of inline `-e` flags |

## ARM Hardware Recommendations

| Device | RAM | Rating | Notes |
|--------|-----|--------|-------|
| **Oracle Cloud A1 Flex** | **24 GB** | ⭐⭐⭐⭐ | **Mejor opción cloud gratuita.** Ampere Altra ARM64, 4 OCPU, 24 GB RAM en [Free Tier](https://www.oracle.com/cloud/free/). Reportado estable con ~230 mods en B41. Ideal para 10-20 jugadores. |
| Raspberry Pi 5 | 8 GB+ | ⭐⭐⭐ | Mejor SBC consumo. Box64 optimizado para Cortex-A76. 5-8 jugadores. |
| Apple Silicon (M1+) | 8 GB+ | ⭐⭐⭐ | Excelente rendimiento vía Docker Desktop. ARM64 nativo + Box64. |
| AWS Graviton2/3 | 4 GB+ | ⭐⭐⭐ | Buena opción cloud paga. Probar con `m6g.large` o superior. |
| Raspberry Pi 4 | 4 GB-8 GB | ⭐⭐ | Funcional con 6-8 jugadores en B41. B42 puede costar. |
| Raspberry Pi 3 | 1 GB-4 GB | ⭐ | RAM limitada. No recomendado para B42. |

## Known Limitations

- First startup downloads ~2GB+ through SteamCMD (slow on low-bandwidth connections)
- Box64 adds ~10-20% CPU overhead vs native x86_64
- Some mods with native x86_64 libraries may not work under Box64
- Build 42 launcher changes may require fallback mode adjustments
- Raspberry Pi 4 with 4GB RAM may experience out-of-memory with large player counts

## Upstream Compatibility

This project aims for env-var compatibility with [indifferentbroccoli/projectzomboid-server-docker](https://github.com/indifferentbroccoli/projectzomboid-server-docker). All upstream env vars are supported. The primary difference is the ARM64 runtime layer (Box64 vs native x86_64).

## Credits

- [sonroyaalmerol/steamcmd-arm64](https://github.com/sonroyaalmerol/steamcmd-arm64) — SteamCMD + Box64 base image
- [gorcon/rcon-cli](https://github.com/gorcon/rcon-cli) — RCON client
- [indifferentbroccoli/projectzomboid-server-docker](https://github.com/indifferentbroccoli/projectzomboid-server-docker) — Reference implementation for env vars and volume contract

## Published Image (GHCR)

This image is automatically built for `linux/arm64` and published to GitHub Container Registry on every merge to the default branch and on semver tag pushes.

### Image Path

```
ghcr.io/<owner>/<repo>
```

Replace `<owner>/<repo>` with the actual GitHub repository path (e.g., `your-org/projectzomboid-server-arm64`). The image name is lowercase regardless of repository casing.

### Available Tags

| Tag Pattern | Generated On | Example |
|-------------|--------------|---------|
| `latest` | Push to default branch (`main`/`master`) | `ghcr.io/owner/repo:latest` |
| `<branch>` | Push to any branch | `ghcr.io/owner/repo:main` |
| `sha-<short>` | Every push | `ghcr.io/owner/repo:sha-a1b2c3d` |
| `<semver>` | Tag push matching `v*.*.*` | `ghcr.io/owner/repo:1.2.3` |
| `<major>.<minor>` | Tag push matching `v*.*.*` | `ghcr.io/owner/repo:1.2` |
| `<major>` | Tag push matching `v*.*.*` | `ghcr.io/owner/repo:1` |

### Pull & Run

```bash
# Pull the latest image
docker pull ghcr.io/<owner>/<repo>:latest

# Run with Docker
docker run -d \
  --name pz-server \
  --platform linux/arm64 \
  -e PASSWORD=CHANGEME \
  -e RCON_PASSWORD=changeme \
  -p 16261:16261/udp \
  -v pz-data:/project-zomboid \
  ghcr.io/<owner>/<repo>:latest

# Override image in docker-compose.yml
# Edit docker-compose.yml and change the `image` field:
#   image: ghcr.io/<owner>/<repo>:latest
```

### Package Visibility

Packages on GHCR default to **private** within the organization/account. To make the image publicly pullable (e.g., for documentation or CI examples):

1. Go to `https://github.com/<owner>/<repo>/pkgs/container/<repo>`
2. Click **Package settings** (gear icon)
3. Under **Danger Zone**, change visibility to **Public**

> **Note:** Anonymous `docker pull` without authentication only works for public packages.

## License

MIT

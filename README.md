# Project Zomboid Dedicated Server -- ARM64

Multi-stage Docker image for Project Zomboid on **ARM64** (Oracle Cloud A1, Raspberry Pi 5, Apple Silicon, AWS Graviton). Runs x86_64 server binary under [Box64](https://github.com/ptitSeb/box64) emulation.

## Quick Start

### Prerequisites

- Docker with buildx
- ARM64 host (or QEMU for testing on amd64)

### Build & Run

```bash
# Build
docker buildx build --platform linux/arm64 -t pz-arm64 .

# Docker Compose (recommended)
cp .env.example .env
# Edit .env -- set PASSWORD, RCON_PASSWORD
docker compose up -d
docker compose logs -f
docker compose stop
```

### With Zomboid Control Panel

```bash
# Enable PanelBridge mod in .env
#   PANEL_BRIDGE_ENABLED=true
docker compose up -d

# Run panel separately
docker run -d --name zomboid-panel -p 3001:3001 ghcr.io/fpsacha/zomboid-control-panel:latest
# Settings -> RCON: <server-ip>:27015
```

### Docker Run

```bash
docker run -d --name pz-server --platform linux/arm64 \
  -e MEMORY_XMX_GB=8 -e PASSWORD=CHANGEME -e RCON_PASSWORD=changeme \
  -p 8766:8766/udp -p 8767:8767/udp -p 16261:16261/udp -p 16262:16262/udp -p 27015:27015/tcp \
  -v pz-data:/project-zomboid -v pz-config:/project-zomboid-config \
  pz-arm64
```

## Essential Environment Variables

Full reference: **[docs/env-variables.md](docs/env-variables.md)**

### Must Change

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSWORD` | `CHANGEME` | Server join password |
| `RCON_PASSWORD` | `changeme` | RCON admin password |

### JVM Memory

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_XMX_GB` | `8` | Max heap in GB |
| `MEMORY_XMS_GB` | *(empty)* | Initial heap (defaults to XMX) |

### PanelBridge (Zomboid Control Panel)

| Variable | Default | Description |
|----------|---------|-------------|
| `PANEL_BRIDGE_ENABLED` | `false` | Auto-install PanelBridge mod from GitHub |
| `PANEL_BRIDGE_VERSION` | `v1.0.26` | Release tag (semver) |

### Key Server Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | `pzserver` | Server name (used as INI filename) |
| `MAX_PLAYERS` | `32` | Max concurrent players |
| `PVP` | `true` | Enable PvP |
| `DO_LUA_CHECKSUM` | `true` | Verify Lua checksum |
| `MODS` | *(empty)* | Semicolon-separated mod IDs |
| `WORKSHOP_ITEMS` | *(empty)* | Workshop item IDs |
| `BRANCH` | *(empty)* | Steam beta branch |
| `UPDATE_ON_START` | `true` | Run SteamCMD update on start |

## Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `pz-data` | `/project-zomboid` | Server saves, mods, logs |
| `pz-config` | `/project-zomboid-config` | Server INI configs |
| `pz-steamapps` | `/steamapps` | SteamCMD cache |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8766 | UDP | Game traffic |
| 8767 | UDP | Game traffic |
| 16261 | UDP | Steam query (`DEFAULT_PORT`) |
| 16262 | UDP | Secondary (`UDP_PORT`) |
| 27015 | TCP | RCON (configurable) |

## Graceful Shutdown

SIGTERM sequence: RCON save -> RCON quit -> wait 30s -> SIGTERM -> wait 5s -> SIGKILL. `stop_grace_period: 90s` in compose.

## Documentation

| Doc | Content |
|-----|---------|
| [docs/env-variables.md](docs/env-variables.md) | Full env var reference + INI mapping |
| [docs/configuration.md](docs/configuration.md) | Config generation, Box64 tuning, Java fallback |
| [docs/deployment.md](docs/deployment.md) | GHCR, CI/CD, build/runtime validation |
| [docs/hardware.md](docs/hardware.md) | ARM device recommendations, limitations |
| [docs/contributing.md](docs/contributing.md) | Validation, CI/CD pipeline |

## Credits

- [sonroyaalmerol/steamcmd-arm64](https://github.com/sonroyaalmerol/steamcmd-arm64) -- SteamCMD + Box64 base image
- [gorcon/rcon-cli](https://github.com/gorcon/rcon-cli) -- RCON client (cross-compiled for ARM64)
- [fpsacha/zomboid-control-panel](https://github.com/fpsacha/zomboid-control-panel) -- Web admin panel + PanelBridge mod
- [indifferentbroccoli/projectzomboid-server-docker](https://github.com/indifferentbroccoli/projectzomboid-server-docker) -- Upstream env var compatibility

## License

MIT

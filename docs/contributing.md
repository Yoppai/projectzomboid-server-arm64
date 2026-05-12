# Contributing

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Stage 1: rcon-builder (golang:1.22-bookworm)              │
│  └─ GOOS=linux GOARCH=arm64 → gorcon/rcon-cli binary       │
├────────────────────────────────────────────────────────────┤
│  Stage 2: final (sonroyaalmerol/steamcmd-arm64:root-bookworm) │
│  ├─ gosu jq nc curl                                        │
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
| `init.sh` | Entrypoint -- validate env, create user, fix perms, run install, gosu to start |
| `functions.sh` | Shared helpers -- `log`, `rcon_send`, `patch_memory_json`, `patch_server_ini` (env-to-INI mapping, PanelBridge mod install), `install_panelbridge`, `wait_for_rcon_port`, `resolve_memory` |
| `install.scmd` | SteamCMD install/update app 380870 with branch support |
| `install_version.scmd` | Helper for manual branch-specific install |
| `start-arm64.sh` | Box64 env setup, memory patching, signal trap, server launch |
| `validate.sh` | Lightweight syntax checks (bash -n, optional shellcheck, docker compose config) |

### Manual Branch Utility

`install_version.scmd` is intentionally not called by the normal startup flow. Use it only for manual SteamCMD branch reinstall/update inside a running container:

```bash
docker exec -it pz-server /opt/pz/scripts/install_version.scmd unstable
```

Normal deployments should use `BRANCH=unstable` in `.env` and restart the container.

## Validation

```bash
./scripts/validate.sh        # Full suite
bash -n scripts/*.sh scripts/*.scmd  # Syntax only
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
```

### Volume ownership validation

```bash
# Check mounted volume ownership matches PUID/PGID
docker run --rm -v pz-data:/data alpine ls -ln /data
```

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/docker-publish.yml`):

- **PRs**: Builds `linux/arm64` image (no push) to validate Dockerfile
- **Push to main/master**: Builds, tags, and publishes to GHCR
- **Semver tags (`v*.*.*`)**: Full publish with versioned tags

Uses `docker/setup-qemu-action@v3`, `docker/build-push-action@v5` with `type=gha` cache, `docker/metadata-action@v5` for OCI labels.

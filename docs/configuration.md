# Server Configuration

## Config Generation

The server configuration lives in `Server/<SERVER_NAME>.ini` inside the config volume.

- **`GENERATE_SETTINGS=true`** (default): On each start, env vars are mapped idempotently to INI keys. Unknown keys and comments are preserved. This is the recommended setting for initial setup and containerized deployments where config is managed through env vars.

- **`GENERATE_SETTINGS=false`**: The INI file is never touched except for minimal required fields (admin credentials, RCON, ports) when the file is first created. Use this to make manual edits to the INI file and have them persist across restarts.

### Env-to-INI Flow

The `env_to_ini_map()` function in `functions.sh` defines the mapping. See [env-variables.md#env-to-ini-mapping](env-variables.md#env-to-ini-mapping) for the full mapping table.

Anti-cheat vars follow a pattern: `ANTI_CHEAT_PROTECTION_TYPE{N}` -> `AntiCheatProtectionType{N}`, with `_THRESHOLD_MULTIPLIER` suffix -> `ThresholdMultiplier` (PascalCase). The `_THRESHOLD` suffix is accepted as an alias for `_THRESHOLD_MULTIPLIER` -- both through compose env and direct script fallback.

---

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

---

## Java Fallback Mode

Set `USE_JAVA_FALLBACK=true` if the Box64 launcher (`ProjectZomboid64`) becomes incompatible (e.g., after a game update). This bypasses the launcher and invokes Java directly:

```bash
docker run -e USE_JAVA_FALLBACK=true ...
```

Additional JVM flags can be passed via `JAVA_EXTRA_ARGS`. Note: Classpath may need adjustment for Build 42 changes. Check game logs if fallback fails.

---

## Build 42 Compatibility

| Risk | Mitigation |
|------|------------|
| Launcher renamed | Set `USE_JAVA_FALLBACK=true` |
| JSON schema changes | `JAVA_EXTRA_ARGS` appends custom flags; jq logs warning |
| Box64 dynarec crash | Set `BOX64_DYNAREC_BIGBLOCK=0` |
| 32-bit helper required | Base image includes Box32; `BOX86_*` vars auto-honored |
| Mod native libs break | Set `GENERATE_SETTINGS=true`, test mods individually, use `GENERATE_SETTINGS=false` to lock known-good config |

---

## Server Branches

Project Zomboid dedicated server is distributed via SteamCMD (App ID `380870`). The `BRANCH` env var controls which beta branch SteamCMD downloads. Set it in `.env` or via `docker run -e BRANCH=unstable`.

| BRANCH value | `-beta` flag | Build | Status | Notes |
|-------------|-------------|-------|--------|-------|
| `""` (empty) | *(none)* | **41** | Stable | Production-ready. Default. |
| `unstable` | `unstable` | **42** | Beta | Multiplayer enabled. Frequent patches. |

> **No other branches exist.** `b41multiplayer`, `prevbuild`, `legacy`, and similar names are not valid SteamCMD beta branches for App 380870. They were either temporary branches that have since been removed, or never existed.

### Build 42 (Unstable) Considerations

- **Saves are not backward-compatible.** A Build 42 world cannot be loaded on Build 41. Keep separate volumes or backup directories if switching branches.
- **Updates can break saves.** The unstable branch receives frequent patches. Always keep backups (`BACKUPS_ON_START=true` is enabled by default).
- **Clients must match.** Every player must opt into the unstable branch in their Steam client (Properties → Betas → Unstable). Version mismatch prevents connection.
- **Mods may be incompatible.** Many Build 41 mods have not been updated for Build 42. Test individually.
- **Higher RAM usage.** Build 42 requires at minimum 8 GB RAM. Set `MEMORY_XMX_GB=8` or higher.
- **Updates on start.** With `UPDATE_ON_START=true` (default), the container downloads the latest unstable patch on every restart. For Build 42 this is recommended to stay current with patches.

To switch to Build 42 unstable:

```bash
# .env
BRANCH=unstable
MEMORY_XMX_GB=10
BACKUPS_ON_START=true
```

To return to Build 41 stable:

```bash
# .env — remove or comment out BRANCH
# BRANCH=unstable
```

> **Note:** Changing branches requires a new SteamCMD download (~2 GB+). The container handles this automatically on next start with `UPDATE_ON_START=true`.

---

## Graceful Shutdown

The container handles `SIGTERM` in this order:

1. Send `save` via RCON
2. Wait 3s for disk flush
3. Send `quit` via RCON
4. Wait 30s for server to exit
5. Send `SIGTERM` to server PID
6. Wait 5s
7. Send `SIGKILL` as last resort

The `stop_grace_period` in `docker-compose.yml` is set to `90s` to accommodate the full shutdown sequence.

---

## PanelBridge Behavior

When `PANEL_BRIDGE_ENABLED=true`, the container automatically:

1. Downloads `mod.info` and `PanelBridge.lua` from the tagged GitHub release
2. Places them in `/project-zomboid/mods/PanelBridge/`
3. Forces `DoLuaChecksum=false` in server INI (required by PanelBridge)
4. Appends `PanelBridge` to `Mods` in server INI

Set `PANEL_BRIDGE_ENABLED=false` to rollback -- next container start cleans PanelBridge from INI automatically.

PanelBridge is pure Lua -- no x86_64 native libs, fully compatible with Box64.

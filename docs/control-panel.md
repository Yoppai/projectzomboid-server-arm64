# Optional Zomboid Control Panel

This repo can work with [`fpsacha/zomboid-control-panel`](https://github.com/fpsacha/zomboid-control-panel), but does not vendor or run it by default.

Default behavior stays vanilla:

- `docker compose up -d` starts only `pz-arm64`.
- Panel web port is not published.
- RCON bind is localhost-only in Compose.
- `PanelBridge` is not downloaded.
- `DoLuaChecksum` stays normal unless `PanelBridge` installs successfully.

## Security model

RCON and the panel are admin planes. Treat them like root access to the server.

- Change `RCON_PASSWORD`, `ADMIN_PASSWORD`, and the panel admin password before use.
- Do not expose RCON or panel directly to the public Internet.
- Defaults bind RCON and panel web to `127.0.0.1` on the Docker host.
- LAN/VPN access requires explicit bind changes and firewall rules.
- Public access is out of MVP: use your own reverse proxy with HTTPS, auth, rate limits, and access controls.
- Never commit `.env` or panel database/log secrets.

## Option A: External panel, docs-only path

Use this when you want to run the upstream panel outside this Compose stack.

1. Download or build upstream release `v1.0.26`:
   - Release/source: <https://github.com/fpsacha/zomboid-control-panel/releases/tag/v1.0.26>
   - Source archive fallback: <https://github.com/fpsacha/zomboid-control-panel/archive/refs/tags/v1.0.26.tar.gz>
2. Persist panel state:
   - `/app/data` for database/config.
   - `/app/logs` for logs.
3. Point panel RCON settings at this server:
   - Same Docker network: `pz-arm64:${RCON_PORT:-27015}`.
   - Host-local panel: `127.0.0.1:${RCON_PORT:-27015}` if using this repo's Compose defaults.
   - LAN/VPN panel: host LAN/VPN address only after explicit `RCON_BIND`/firewall opt-in.
4. Use `RCON_PASSWORD` from `.env`.

Source build fallback:

```bash
git clone --branch v1.0.26 --depth 1 https://github.com/fpsacha/zomboid-control-panel.git
cd zomboid-control-panel
docker build -t zomboid-control-panel:v1.0.26 .
docker run --rm -p 127.0.0.1:3001:3001 \
  -v zomboid-panel-data:/app/data \
  -v zomboid-panel-logs:/app/logs \
  zomboid-control-panel:v1.0.26
```

## Option B: Compose profile

The repo includes an optional `zomboid-panel` profile. It builds upstream `v1.0.26` from GitHub and stores data in named volumes.

```bash
cp .env.example .env
# Edit .env: strong PASSWORD, RCON_PASSWORD, ADMIN_PASSWORD
docker compose --profile zomboid-panel up -d --build
```

Open: <http://127.0.0.1:3001>

First-time panel RCON target:

- Host: `pz-arm64`
- Port: `${RCON_PORT:-27015}`
- Password: your `.env` `RCON_PASSWORD`

Panel profile vars:

| Var | Default | Notes |
|---|---|---|
| `PANEL_BIND` | `127.0.0.1` | Web bind on Docker host. Use LAN/VPN IP only intentionally. |
| `PANEL_PORT` | `3001` | Host web port. |
| `PANEL_SOURCE_URL` | `https://github.com/fpsacha/zomboid-control-panel.git#v1.0.26` | Compose build context. Pin tags; avoid `latest`. |

Volumes:

- `panel-data` -> `/app/data`
- `panel-logs` -> `/app/logs`

## Option C: PanelBridge server mod

PanelBridge enables advanced panel features beyond plain RCON. It changes server-side Lua behavior, so it is opt-in.

Enable only after you trust the pinned upstream source:

```env
PANEL_BRIDGE_ENABLED=true
PANEL_BRIDGE_VERSION=v1.0.26
# Optional supply-chain pin:
# PANEL_BRIDGE_SHA256=<sha256 of source tar.gz>
```

On next container start, helper downloads:

```text
https://github.com/fpsacha/zomboid-control-panel/archive/refs/tags/${PANEL_BRIDGE_VERSION}.tar.gz
```

Then it extracts only:

```text
pz-mod/PanelBridge/
```

Install path:

```text
/project-zomboid/mods/PanelBridge
```

Validation requires:

- `mod.info`
- at least one `media/lua/server/*.lua`

When install succeeds, `server.ini` gets:

- `Mods=...;PanelBridge`
- `DoLuaChecksum=false`

Checksum tradeoff: `DoLuaChecksum=false` is required for PanelBridge but weakens Lua integrity checks. The helper only sets it when PanelBridge installs successfully.

Manual fallback if upstream layout drifts:

1. Download pinned source archive for `v1.0.26`.
2. Extract `pz-mod/PanelBridge/`.
3. Place it in `/project-zomboid/mods/PanelBridge`.
4. Set `MODS=PanelBridge` or include it in your existing semicolon list.
5. Set `DO_LUA_CHECKSUM=false` knowingly.
6. Restart server.

## Validation / smoke checks

Default path:

```bash
docker compose config
docker compose up -d
docker compose ps
```

Expected:

- No `zomboid-panel` container unless profile is used.
- RCON published as `127.0.0.1:${RCON_PORT:-27015}`, not `0.0.0.0`.
- No `/project-zomboid/mods/PanelBridge` unless `PANEL_BRIDGE_ENABLED=true`.

Profile path:

```bash
docker compose --profile zomboid-panel config
docker compose --profile zomboid-panel up -d --build
docker compose ps
```

Expected:

- UI: <http://127.0.0.1:3001>
- `panel-data` and `panel-logs` volumes exist.
- Panel connects to RCON target `pz-arm64:${RCON_PORT:-27015}` from inside Compose network.

Bridge path:

```bash
docker compose exec pz-arm64 test -f /project-zomboid/mods/PanelBridge/mod.info
docker compose exec pz-arm64 grep -E '^(Mods|DoLuaChecksum)=' /project-zomboid-config/Server/${SERVER_NAME:-pzserver}.ini
```

Expected when enabled and installed:

- `Mods` contains `PanelBridge`.
- `DoLuaChecksum=false`.

## Rollback

Disable panel profile:

```bash
docker compose down
docker compose up -d
```

Disable PanelBridge:

```env
PANEL_BRIDGE_ENABLED=false
DO_LUA_CHECKSUM=true
```

Restart:

```bash
docker compose up -d --force-recreate
```

The helper skips downloads. INI patching removes auto-managed `PanelBridge` from `Mods` when it was not explicitly set by `MODS`.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| GitHub tag/path drift | Helper says `pz-mod/PanelBridge` missing | Use manual fallback or update `PANEL_BRIDGE_VERSION` after verifying upstream. |
| Checksum mismatch | Helper says checksum mismatch | Recalculate sha256 for the exact source archive or leave `PANEL_BRIDGE_SHA256` empty while testing. |
| Panel image unavailable | Compose build fails | Build from source via `PANEL_SOURCE_URL` or external docs-only path. |
| RCON auth fails | Panel cannot connect/login | Verify `RCON_PASSWORD`, host `pz-arm64`, port `${RCON_PORT:-27015}`, and server restart. |
| Port conflict | `3001` already used | Set `PANEL_PORT=3002` and reopen `http://127.0.0.1:3002`. |
| Remote browser cannot open panel | Default localhost bind | Use SSH tunnel/VPN, or explicitly set `PANEL_BIND` to trusted LAN IP. Public reverse proxy is user-managed. |
| Bridge changes not visible | Server still running old config | Restart server after mod/config changes. |

## Non-goals

- Vendoring upstream panel/mod code in this repository.
- Public panel/RCON exposure by default.
- Built-in reverse proxy, HTTPS, SSO, or auth hardening.
- Advanced multi-server management.

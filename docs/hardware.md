# Hardware & Compatibility

## ARM Hardware Recommendations

| Device | RAM | Rating | Notes |
|--------|-----|--------|-------|
| **Oracle Cloud A1 Flex** | **24 GB** | Excellent | Best free cloud option. Ampere Altra ARM64, 4 OCPU, 24 GB RAM on Free Tier. Reported stable with ~230 mods on B41. Ideal for 10-20 players. |
| Raspberry Pi 5 | 8 GB+ | Great | Best SBC for power consumption. Box64 optimized for Cortex-A76. 5-8 players. |
| Apple Silicon (M1+) | 8 GB+ | Great | Excellent performance via Docker Desktop. ARM64 native + Box64. |
| AWS Graviton2/3 | 4 GB+ | Good | Solid paid cloud option. Try `m6g.large` or higher. |
| Raspberry Pi 4 | 4 GB-8 GB | Fair | Functional with 6-8 players on B41. B42 may struggle. |
| Raspberry Pi 3 | 1 GB-4 GB | Poor | RAM limited. Not recommended for B42. |

---

## Known Limitations

- First startup downloads ~2GB+ through SteamCMD (slow on low-bandwidth connections)
- Box64 adds ~10-20% CPU overhead vs native x86_64
- Some mods with native x86_64 libraries may not work under Box64
- PanelBridge is pure Lua -- no x86_64 native libs, fully compatible with Box64
- Build 42 launcher changes may require fallback mode adjustments
- Raspberry Pi 4 with 4GB RAM may experience out-of-memory with large player counts

---

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

---

## Upstream Compatibility

This project aims for env-var compatibility with [indifferentbroccoli/projectzomboid-server-docker](https://github.com/indifferentbroccoli/projectzomboid-server-docker). All upstream env vars are supported. The primary difference is the ARM64 runtime layer (Box64 vs native x86_64).

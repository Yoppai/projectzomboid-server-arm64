# Deployment & CI/CD

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

Note: Anonymous `docker pull` without authentication only works for public packages.

---

## CI/CD

This project uses a GitHub Actions workflow (`.github/workflows/docker-publish.yml`) that:

- **PRs**: Builds the `linux/arm64` image (no push) to validate Dockerfile and build context
- **Push to main/master**: Builds, tags, and publishes to GHCR
- **Semver tags (`v*.*.*`)**: Triggers full publish with versioned tags

The workflow uses:
- `docker/setup-qemu-action@v3` for ARM64 cross-platform emulation
- `docker/build-push-action@v5` with GitHub Actions cache (`type=gha`)
- `docker/metadata-action@v5` for automatic OCI labels and semver tag generation

---

## Build Validation

```bash
# Shellcheck all scripts
shellcheck scripts/*.sh scripts/*.scmd

# Verify Dockerfile syntax + build
docker buildx build --platform linux/arm64 -t pz-arm64 .
```

---

## Binary Validation

```bash
# Check rcon binary architecture
docker run --rm --platform linux/arm64 pz-arm64 file /usr/local/bin/rcon
# Expected: ELF 64-bit LSB executable, ARM aarch64
```

---

## Runtime Validation

```bash
# Start with compose
docker compose up

# Expected log sequence:
# 1. Box64 env vars exported
# 2. SteamCMD app_update 380870
# 3. Server listening on ports

# Test graceful shutdown
docker stop --time 90 <container_name>

# Check RCON save/quit in logs:
# RCON save command sent -> RCON quit command sent -> server exits cleanly
```

---

## Volume Ownership Validation

```bash
# Check mounted volume ownership matches PUID/PGID
docker run --rm -v pz-data:/data alpine ls -ln /data
```

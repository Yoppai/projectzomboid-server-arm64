# =============================================================================
# Project Zomboid Dedicated Server — ARM64 via Box64
# Multi-stage build: cross-compile RCON CLI + final runtime image
# =============================================================================

# Stage 1: Cross-compile gorcon/rcon-cli for linux/arm64
# Uses BUILDPLATFORM (e.g., amd64) to run Go compiler natively while
# targeting arm64 — avoids QEMU emulation during build.
FROM --platform=$BUILDPLATFORM golang:1.22-bookworm AS rcon-builder

ARG TARGETARCH
ARG TARGETOS
ARG RCON_CLI_VERSION=v0.10.3

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/gorcon/rcon-cli.git .

# Attempt checkout of pinned version; fall back to master
RUN git checkout "${RCON_CLI_VERSION}" 2>/dev/null || \
    echo "RCON pin ${RCON_CLI_VERSION} not found, using master"

ENV GOOS=${TARGETOS:-linux} \
    GOARCH=${TARGETARCH:-arm64} \
    CGO_ENABLED=0

RUN go build -ldflags="-s -w" -o /bin/rcon ./cmd/gorcon/ && \
    file /bin/rcon

# =============================================================================
# Stage 2: Final ARM64 runtime image
# =============================================================================
FROM sonroyaalmerol/steamcmd-arm64:root-bookworm@sha256:4e09bdb6723db7aca5142808e32c08873f836d28012b8696913770987741f6e6

# --- Build-time defaults (overridable via --build-arg) ---
ARG PUID=1000
ARG PGID=1000
ARG MEMORY=2G
ARG BRANCH=""
ARG RCON_PORT=27015
ARG UPDATE_ON_START=true
ARG USE_JAVA_FALLBACK=false
ARG BOX64_VERSION=v0.2.4
ARG BOX64_DYNAREC_BIGBLOCK=0
ARG BOX64_DYNAREC_BLEEDING_EDGE=0

# --- Runtime dependencies ---
# gosu: drop privileges cleanly
# jq:   patch ProjectZomboid64.json memory config
# netcat-openbsd (nc): RCON port readiness check
RUN apt-get update && apt-get install -y --no-install-recommends \
        gosu \
        jq \
        netcat-openbsd \
        curl \
        file \
        libsm6 \
        libice6 \
        libx11-6 \
        libx11-dev \
        libxext6 \
        libxext-dev \
    && rm -rf /var/lib/apt/lists/*

# sonroyaalmerol/steamcmd-arm64 stores SteamCMD under /home/steam/steamcmd.
# Keep the Debian-style path expected by older scripts and docs. Use a wrapper,
# not a symlink: steamcmd.sh resolves linux32/steamcmd relative to $0.
RUN set -eux; \
    if ! command -v steamcmd >/dev/null 2>&1 && [ ! -e /usr/games/steamcmd ]; then \
        found="$(find /home/steam /opt /root -name steamcmd.sh 2>/dev/null | head -n 1)"; \
        test -n "$found"; \
        mkdir -p /usr/games; \
        steamdir="$(dirname "$found")"; \
        printf '#!/bin/sh\ncd "%s"\nexec ./steamcmd.sh "$@"\n' "$steamdir" > /usr/games/steamcmd; \
        chmod +x /usr/games/steamcmd; \
    fi

# Optionally rebuild Box64 from a pinned source version. Empty BOX64_VERSION keeps base image Box64.
RUN set -eux; \
    if [ -n "${BOX64_VERSION}" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            build-essential \
            ca-certificates \
            cmake \
            git \
            python3; \
        git clone --depth 1 --branch "${BOX64_VERSION}" https://github.com/ptitSeb/box64.git /tmp/box64; \
        cmake -S /tmp/box64 -B /tmp/box64/build \
            -DRPI4ARM64=1 \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo; \
        cmake --build /tmp/box64/build --parallel "$(nproc)"; \
        cmake --install /tmp/box64/build; \
        box64 --version; \
        rm -rf /tmp/box64; \
        apt-get purge -y --auto-remove build-essential cmake git python3; \
        rm -rf /var/lib/apt/lists/*; \
    else \
        box64 --version || true; \
    fi

# --- Copy cross-compiled RCON binary ---
COPY --from=rcon-builder /bin/rcon /usr/local/bin/rcon

# --- Copy scripts ---
COPY scripts/functions.sh       /opt/pz/scripts/functions.sh
COPY scripts/init.sh            /opt/pz/scripts/init.sh
COPY scripts/install.scmd       /opt/pz/scripts/install.scmd
COPY scripts/install_version.scmd /opt/pz/scripts/install_version.scmd
COPY scripts/start-arm64.sh     /opt/pz/scripts/start-arm64.sh
COPY scripts/validate.sh        /opt/pz/scripts/validate.sh

RUN chmod +x /opt/pz/scripts/*.sh /opt/pz/scripts/*.scmd

# --- Volumes for persistence ---
VOLUME ["/project-zomboid", "/project-zomboid-config", "/steamapps"]

# --- Ports ---
# Game traffic
EXPOSE 8766/udp 8767/udp
# Steam query / master server
EXPOSE 16261/udp 16262/udp
# RCON (configurable)
EXPOSE 27015/tcp

# --- Persist ARG defaults as runtime ENV ---
ENV PUID=${PUID} \
    PGID=${PGID} \
    MEMORY=${MEMORY} \
    BRANCH=${BRANCH} \
    RCON_PORT=${RCON_PORT} \
    UPDATE_ON_START=${UPDATE_ON_START} \
    USE_JAVA_FALLBACK=${USE_JAVA_FALLBACK} \
    BOX64_DYNAREC_BIGBLOCK=${BOX64_DYNAREC_BIGBLOCK} \
    BOX64_DYNAREC_BLEEDING_EDGE=${BOX64_DYNAREC_BLEEDING_EDGE} \
    GENERATE_SETTINGS=true \
    SERVER_NAME=pzserver \
    MEMORY_XMX_GB=2 \
    MEMORY_XMS_GB= \
    DISABLE_STEAM=false \
    JAVA_EXTRA_ARGS= \
    ARM64_DEVICE= \
    BACKUPS_ON_START=true \
    BACKUPS_ON_VERSION_CHANGE=true

HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=5 \
    CMD nc -z 127.0.0.1 "${RCON_PORT:-27015}" || exit 1

ENTRYPOINT ["/opt/pz/scripts/init.sh"]

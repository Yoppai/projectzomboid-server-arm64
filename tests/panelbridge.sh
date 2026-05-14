#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../scripts/functions.sh
source "$PROJECT_DIR/scripts/functions.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -qF -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    ! grep -qF -- "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

assert_line_count() {
    local expected="$1"
    local pattern="$2"
    local file="$3"
    local count
    count=$(grep -cE -- "$pattern" "$file" || true)
    [[ "$count" == "$expected" ]] || fail "expected $expected lines matching $pattern in $file, got $count"
}

make_panelbridge_archive() {
    local root="$1"
    local archive="$2"
    local source_dir="$root/zomboid-control-panel-1.0.26/pz-mod/PanelBridge"

    mkdir -p "$source_dir/media/lua/server"
    cat > "$source_dir/mod.info" <<'MODINFO'
name=PanelBridge
id=PanelBridge
MODINFO
    cat > "$source_dir/media/lua/server/PanelBridgeServer.lua" <<'LUA'
print("PanelBridge test fixture")
LUA

    tar -czf "$archive" -C "$root" "zomboid-control-panel-1.0.26"
}

make_mock_curl() {
    local bin_dir="$1"
    cat > "$bin_dir/curl" <<'MOCKCURL'
#!/bin/bash
set -euo pipefail
output=""
url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done
[[ -n "$output" ]] || exit 2
[[ "$url" == file://* ]] || exit 3
cp "${url#file://}" "$output"
MOCKCURL
    chmod +x "$bin_dir/curl"
}

test_install_panelbridge_places_files() {
    local tmp archive mock_bin pz_dir config_dir ini
    tmp="$(mktemp -d)"
    archive="$tmp/panelbridge.tar.gz"
    mock_bin="$tmp/bin"
    pz_dir="$tmp/project-zomboid"
    config_dir="$tmp/project-zomboid-config"
    mkdir -p "$mock_bin" "$pz_dir" "$config_dir/Server"
    make_panelbridge_archive "$tmp/src" "$archive"
    make_mock_curl "$mock_bin"

    PATH="$mock_bin:$PATH" \
    PANEL_BRIDGE_ENABLED=true \
    PANEL_BRIDGE_VERSION=v1.0.26 \
    PANEL_BRIDGE_SOURCE_URL="file://$archive" \
    PROJECT_ZOMBOID_DIR="$pz_dir" \
    install_panelbridge

    assert_file "$pz_dir/mods/PanelBridge/mod.info"
    assert_file "$pz_dir/mods/PanelBridge/media/lua/server/PanelBridgeServer.lua"
    [[ "${PANEL_BRIDGE_INSTALLED:-}" == "true" ]] || fail "PANEL_BRIDGE_INSTALLED not true"

    ini="$config_dir/Server/pzserver.ini"
    SERVER_NAME=pzserver \
    CONFIG_DIR="$config_dir" \
    PROJECT_ZOMBOID_DIR="$pz_dir" \
    GENERATE_SETTINGS=true \
    PANEL_BRIDGE_ENABLED=true \
    PANEL_BRIDGE_INSTALLED=true \
    DO_LUA_CHECKSUM=true \
    MODS=ExampleMod \
    patch_server_ini

    assert_contains "$ini" "Mods=ExampleMod;PanelBridge"
    assert_contains "$ini" "DoLuaChecksum=false"
    assert_line_count 1 '^Mods=.*PanelBridge' "$ini"

    SERVER_NAME=pzserver \
    CONFIG_DIR="$config_dir" \
    PROJECT_ZOMBOID_DIR="$pz_dir" \
    GENERATE_SETTINGS=true \
    PANEL_BRIDGE_ENABLED=true \
    PANEL_BRIDGE_INSTALLED=true \
    DO_LUA_CHECKSUM=true \
    MODS=ExampleMod \
    patch_server_ini

    assert_contains "$ini" "Mods=ExampleMod;PanelBridge"
    assert_line_count 1 '^Mods=.*PanelBridge' "$ini"
    rm -rf "$tmp"
}

test_patch_server_ini_disabled_rollback_is_idempotent() {
    local tmp pz_dir config_dir ini
    tmp="$(mktemp -d)"
    pz_dir="$tmp/project-zomboid"
    config_dir="$tmp/project-zomboid-config"
    ini="$config_dir/Server/pzserver.ini"
    mkdir -p "$pz_dir/mods" "$config_dir/Server"
    cat > "$ini" <<'INI'
Mods=ExampleMod;PanelBridge
DoLuaChecksum=false
INI

    SERVER_NAME=pzserver \
    CONFIG_DIR="$config_dir" \
    PROJECT_ZOMBOID_DIR="$pz_dir" \
    GENERATE_SETTINGS=true \
    PANEL_BRIDGE_ENABLED=false \
    PANEL_BRIDGE_INSTALLED=false \
    DO_LUA_CHECKSUM=true \
    MODS= \
    patch_server_ini

    assert_contains "$ini" "Mods=ExampleMod"
    assert_not_contains "$ini" "PanelBridge"
    assert_contains "$ini" "DoLuaChecksum=true"

    SERVER_NAME=pzserver \
    CONFIG_DIR="$config_dir" \
    PROJECT_ZOMBOID_DIR="$pz_dir" \
    GENERATE_SETTINGS=true \
    PANEL_BRIDGE_ENABLED=false \
    PANEL_BRIDGE_INSTALLED=false \
    DO_LUA_CHECKSUM=true \
    MODS= \
    patch_server_ini

    assert_contains "$ini" "Mods=ExampleMod"
    assert_not_contains "$ini" "PanelBridge"
    assert_line_count 1 '^Mods=ExampleMod$' "$ini"
    rm -rf "$tmp"
}

test_patch_server_ini_skips_empty_env_and_keeps_generated_values() {
    local tmp config_dir ini
    tmp="$(mktemp -d)"
    config_dir="$tmp/project-zomboid-config"
    ini="$config_dir/Server/pzserver.ini"
    mkdir -p "$config_dir/Server"
    cat > "$ini" <<'INI'
PVP=true
DefaultPort=16261
AntiCheatProtectionType24ThresholdMultiplier=6.0
AdminUsername=oldadmin
INI

    SERVER_NAME=pzserver \
    CONFIG_DIR="$config_dir" \
    GENERATE_SETTINGS=true \
    PVP= \
    DEFAULT_PORT= \
    ANTI_CHEAT_PROTECTION_TYPE24_THRESHOLD_MULTIPLIER= \
    ADMIN_USERNAME=admin \
    patch_server_ini

    assert_contains "$ini" "PVP=true"
    assert_contains "$ini" "DefaultPort=16261"
    assert_contains "$ini" "AntiCheatProtectionType24ThresholdMultiplier=6.0"
    assert_contains "$ini" "AdminUsername=admin"
    assert_not_contains "$ini" "6.0AdminUsername"
    assert_line_count 1 '^AdminUsername=admin$' "$ini"
    rm -rf "$tmp"
}

test_install_panelbridge_places_files
test_patch_server_ini_disabled_rollback_is_idempotent
test_patch_server_ini_skips_empty_env_and_keeps_generated_values

echo "[PASS] PanelBridge install and INI patch tests"

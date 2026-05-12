#!/bin/bash
# =============================================================================
# validate.sh — Lightweight local validation for Project Zomboid ARM64 server
#
# Performs:
#   1. bash -n syntax check on all shell scripts
#   2. Optional shellcheck if installed
#   3. docker compose config if Docker is available (no build/pull)
#      — treats Docker Desktop context failures as warnings, not errors
#   4. Env completeness check:
#      a) Every var in .env.example appears in docker-compose.yml environment
#      b) Every env-to-ini mapped var exists in .env.example
#
# Does NOT build, pull, or download anything.
# Returns 0 on all-pass, non-zero on first failure.
# =============================================================================

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colours for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

pass_msg() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail_msg() { echo -e "  ${RED}[FAIL]${NC} $1"; }
warn_msg() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }

echo "============================================"
echo " validate.sh — Lightweight Syntax Checks"
echo " Project: $(basename "$PROJECT_DIR")"
echo "============================================"

# --- 1. bash -n on all .sh and .scmd files ---
echo ""
echo "--- Step 1/4: bash -n syntax check ---"

SYNTAX_FAIL=0
while IFS= read -r -d '' script; do
    name="$(basename "$script")"
    if bash -n "$script" 2>/dev/null; then
        pass_msg "bash -n: $name"
    else
        fail_msg "bash -n: $name"
        bash -n "$script" 2>&1 | sed 's/^/         /'
        SYNTAX_FAIL=1
    fi
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.scmd' \) -print0)

if [[ $SYNTAX_FAIL -eq 1 ]]; then
    ERRORS=$((ERRORS + 1))
else
    echo "  All scripts pass bash -n"
fi

# --- 2. Optional shellcheck ---
echo ""
echo "--- Step 2/4: shellcheck (optional) ---"

if command -v shellcheck &>/dev/null; then
    echo "  shellcheck found — running..."
    while IFS= read -r -d '' script; do
        name="$(basename "$script")"
        if shellcheck -s bash "$script" 2>/dev/null; then
            pass_msg "shellcheck: $name"
        else
            warn_msg "shellcheck: $name (review warnings)"
            shellcheck -s bash "$script" 2>&1 | sed 's/^/         /'
        fi
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.scmd' \) -print0)
else
    echo "  shellcheck not installed — skipping (install with: apt install shellcheck / brew install shellcheck)"
fi

# --- 3. docker compose config (graceful context check) ---
echo ""
echo "--- Step 3/4: docker compose config (optional) ---"

compose_check() {
    # Try primary check
    local output
    output=$(docker compose config 2>&1)
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        pass_msg "docker compose config renders successfully"
        return 0
    fi

    # Check if failure is context-related (WSL/Git Bash Docker Desktop)
    if echo "$output" | grep -qiE "(context|Desktop|not running|connection refused|cannot connect|daemon)" 2>/dev/null; then
        warn_msg "docker compose config unavailable in this shell environment"
        echo "         Reason: $(echo "$output" | head -1)"
        echo "         Suggestion: Run from Windows PowerShell directly:"
        echo "           docker compose config"
        return 0  # Not counting as error
    fi

    # Real compose error — report as failure
    fail_msg "docker compose config failed"
    echo "$output" | sed 's/^/         /'
    return 1
}

if command -v docker &>/dev/null; then
    compose_check || ERRORS=$((ERRORS + 1))
else
    echo "  docker not found — skipping compose config check"
fi

# --- 4. Env completeness check ---
echo ""
echo "--- Step 4/4: Env completeness check ---"

ENVFILE="$PROJECT_DIR/.env.example"
COMPOSEFILE="$PROJECT_DIR/docker-compose.yml"
FUNCTIONSFILE="$SCRIPT_DIR/functions.sh"

MAPPING_MISSING=0

# Alias map: vars aliased by a differently-named primary in compose
# Format: "ALIASED_VAR:PRIMARY_VAR"
declare -a ALIAS_MAP=(
    "PUBLIC:SERVER_PUBLIC"
)

_check_alias_resolved() {
    local var="$1"
    local alias_entry alias primary
    for alias_entry in "${ALIAS_MAP[@]}"; do
        alias="${alias_entry%%:*}"
        primary="${alias_entry##*:}"
        if [[ "$var" == "$alias" ]]; then
            # Use grep -F (fixed string) to avoid ERE $ anchor issues
            local needle="- ${primary}=\${${primary}:-"
            if grep -qF -- "$needle" "$COMPOSEFILE"; then
                pass_msg "${var} (aliased by ${primary})"
                return 0
            fi
        fi
    done
    return 1
}

check_env_in_compose() {
    echo "  Checking .env.example vars in docker-compose.yml environment..."

    # Extract all variable names from .env.example (non-comment, non-blank lines)
    local env_vars=()
    while IFS='=' read -r name _; do
        # Skip comments, blank, and section headers like [Category]
        [[ -z "$name" || "$name" =~ ^[[:space:]]*# || "$name" =~ ^[[:space:]]*\[ ]] && continue
        name="${name%%[[:space:]]*}"  # Trim trailing whitespace
        # Strip possible \r from CRLF line endings
        name="${name%%$'\r'}"
        env_vars+=("$name")
    done < "$ENVFILE"

    local missing=0
    for var in "${env_vars[@]}"; do
        # 1) Interpolated: - VAR=${VAR:-default}
        # Use grep -F (fixed string) to avoid ERE $ anchor issues on Git Bash / MSYS2
        local needle="- ${var}=\${${var}:-"
        if grep -qF -- "$needle" "$COMPOSEFILE"; then
            pass_msg "${var} (interpolated)"
            continue
        fi

        # 2) Alias: var is aliased by primary which IS interpolated
        if _check_alias_resolved "$var"; then
            continue
        fi

        # 3) Intentionally static: hardcoded with # compose-static annotation
        if grep -qE "^\s+- ${var}=[^$].*# compose-static" "$COMPOSEFILE"; then
            pass_msg "${var} (hardcoded, compose-static)"
            continue
        fi

        # 4) Intentionally excluded: # compose-excluded: VAR
        if grep -qE "# compose-excluded: ${var}([^a-zA-Z0-9_]|$)" "$COMPOSEFILE"; then
            pass_msg "${var} (intentionally excluded per compose-excluded comment)"
            continue
        fi

        # 5) Not in compose — info only (compose is intentionally minimal)
        warn_msg "${var} not in docker-compose.yml (use docker run -e or add to compose)"
        missing=1
    done

    if [[ $missing -eq 0 ]]; then
        echo "    All .env.example vars present in compose environment"
    else
        echo "    ${missing} vars not in compose — add manually if needed, or use docker run -e"
        echo "    Compose is intentionally minimal. Full reference: docs/env-variables.md"
    fi
}

check_mapping_completeness() {
    echo "  Checking env-to-ini mapping coverage..."

    if [[ ! -f "$FUNCTIONSFILE" ]]; then
        warn_msg "functions.sh not found — skipping mapping check"
        return
    fi

    # Source functions to get mapping
    # shellcheck disable=SC1090
    source "$FUNCTIONSFILE" 2>/dev/null || {
        warn_msg "Cannot source functions.sh — skipping mapping check"
        return
    }

    # Collect all env var names from env_to_ini_map + anti-cheat
    local mapped_vars=()
    while IFS= read -r line; do
        # Skip blank lines and comment lines (including section headers like "# === ... ===")
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        local env_name="${line#*=}"
        local ini_key="${line%%=*}"
        [[ -z "$env_name" || -z "$ini_key" ]] && continue
        mapped_vars+=("$env_name")
    done < <(env_to_ini_map; env_to_ini_anticheat_map)

    if [[ ${#mapped_vars[@]} -eq 0 ]]; then
        warn_msg "No mapped vars found — env_to_ini_map may be empty"
        return
    fi

    local missing=0
    for var in "${mapped_vars[@]}"; do
        # Check var exists in .env.example
        if ! grep -qE "^${var}=" "$ENVFILE" 2>/dev/null; then
            # Allow intentionally unmapped (not all env vars are INI settings)
            if grep -qE "# ini-unmapped: ${var}([^a-zA-Z0-9_]|$)" "$ENVFILE" 2>/dev/null; then
                pass_msg "${var} (intentionally unmapped per ini-unmapped comment)"
            else
                warn_msg "${var} mapped in env_to_ini but missing from .env.example"
                missing=1
            fi
        fi
    done

    if [[ $missing -eq 0 ]]; then
        echo "    All mapped env vars present in .env.example"
    else
        MAPPING_MISSING=1
        echo "    Some mapped vars missing from .env.example — add them or annotate with # ini-unmapped: VARNAME"
    fi
}

check_env_in_compose
check_mapping_completeness

if [[ $MAPPING_MISSING -eq 1 ]]; then
    ERRORS=$((ERRORS + 1))
fi

# --- Summary ---
echo ""
echo "============================================"
if [[ $ERRORS -eq 0 ]]; then
    echo -e " ${GREEN}Result: ALL CHECKS PASSED${NC}"
    exit 0
else
    echo -e " ${RED}Result: $ERRORS check(s) FAILED${NC}"
    exit 1
fi
echo "============================================"

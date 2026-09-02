#!/usr/bin/env bash
# Shared helpers: colors, logging, error handling, OS checks.
# Sourced by build.sh; never executed directly.

set -uo pipefail

ROOT_DIR="${ROOT_DIR:?ROOT_DIR must be set before sourcing common.sh}"
LOG_FILE="${LOG_FILE:-}"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

_log_line() {
    [[ -n "$LOG_FILE" ]] && printf '%s\n' "$1" >> "$LOG_FILE"
}

log_ok()    { local msg="[ OK ] $1";   printf '%s%s%s\n' "$C_GREEN"  "$msg" "$C_RESET"; _log_line "$msg"; }
log_warn()  { local msg="[ WARN ] $1"; printf '%s%s%s\n' "$C_YELLOW" "$msg" "$C_RESET"; _log_line "$msg"; }
log_err()   { local msg="[ ERROR ] $1"; printf '%s%s%s\n' "$C_RED"   "$msg" "$C_RESET" >&2; _log_line "$msg"; }
log_info()  { local msg="[ INFO ] $1"; printf '%s%s%s\n' "$C_BLUE"  "$msg" "$C_RESET"; _log_line "$msg"; }

# die MESSAGE...  -- prints each line prefixed as an ERROR, logs, exits 1.
# This is the single stop-the-build primitive: every check in this project
# fails through die(), never through a silent return, so a partial/damaged
# ROM can never be reported as a success (see spec principle: better to
# stop than build a damaged ROM).
die() {
    local line
    for line in "$@"; do
        log_err "$line"
    done
    _log_line "BUILD FAILED"
    exit 1
}

# run_logged CMD...  -- runs a command, tees its output into the log file,
# dies with the command's own stderr tail on non-zero exit.
run_logged() {
    _log_line "+ $*"
    local out
    if ! out="$("$@" 2>&1)"; then
        local status=$?
        _log_line "$out"
        die "Command failed (exit $status): $*" "$(tail -n 20 <<<"$out")"
    fi
    _log_line "$out"
    printf '%s\n' "$out"
}

human_bytes() {
    local b=$1
    if (( b >= 1048576 )); then
        printf '%s MiB' "$(( b / 1048576 ))"
    else
        printf '%s bytes' "$b"
    fi
}

check_os() {
    local os_id="" os_like="" version=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="${ID:-}"; os_like="${ID_LIKE:-}"; version="${VERSION_ID:-}"
    fi

    case "$os_id $os_like" in
        *ubuntu*|*debian*) : ;;
        *)
            die "ERROR: Unsupported OS." \
                "This tool targets Ubuntu LTS or Debian (stable/testing)." \
                "Detected: ID='${os_id:-unknown}' ID_LIKE='${os_like:-unknown}'" \
                "STOP."
            ;;
    esac
    log_ok "OS: ${PRETTY_NAME:-$os_id $version}"

    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "x86_64" ]]; then
        die "ERROR: Unsupported architecture." \
            "Expected: x86_64" \
            "Actual: $arch" \
            "STOP."
    fi
    log_ok "Architecture: $arch"

    if [[ -z "${BASH_VERSINFO:-}" || "${BASH_VERSINFO[0]}" -lt 5 ]]; then
        die "ERROR: Bash 5+ is required (found ${BASH_VERSION:-unknown})."
    fi
    log_ok "Bash: $BASH_VERSION"
}

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

confirm() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

#!/usr/bin/env bash
# Dependency detection. Never installs anything itself -- only ever prints
# the exact apt command for the user to run. This is a deliberate choice
# (confirmed with the user): automatically running `sudo apt install` from
# an unattended script is exactly the kind of system-modifying action this
# project avoids taking on the user's behalf.

# Tools this wrapper script itself needs, independent of whatever lbmk's
# own `./mk dependencies <distro>` step pulls in for the coreboot build.
WRAPPER_DEPS=(git curl sha256sum make gcc g++ python3 pkg-config xz gzip
              bzip2 unzip cpio tar file hexdump xxd dd)

check_wrapper_deps() {
    local missing=()
    local bin
    for bin in "${WRAPPER_DEPS[@]}"; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_ok "Dependencies (wrapper script)"
        return 0
    fi

    log_err "Missing wrapper-script dependencies: ${missing[*]}"
    print_apt_hint "${missing[@]}"
    return 1
}

# Map a couple of our tool names to their actual Debian/Ubuntu package
# names where they differ (most are already package names).
declare -A APT_PKG_OVERRIDE=(
    [g++]="g++"
    [gcc]="gcc"
    [sha256sum]="coreutils"
    [hexdump]="bsdmainutils"
    [xxd]="xxd"
    [dd]="coreutils"
)

print_apt_hint() {
    local pkgs=() bin pkg seen=()
    for bin in "$@"; do
        pkg="${APT_PKG_OVERRIDE[$bin]:-$bin}"
        [[ " ${seen[*]:-} " == *" $pkg "* ]] && continue
        seen+=("$pkg")
        pkgs+=("$pkg")
    done
    log_info "Install with:"
    printf '    sudo apt-get update && sudo apt-get install -y %s\n' "${pkgs[*]}"
}

# print_libreboot_apt_hint DISTRO -- reads the *real* package list lbmk
# itself declares for the given distro (config/dependencies/<distro> inside
# the cloned repo) and prints the exact command lbmk would run internally
# via `./mk dependencies <distro>`, so the user installs precisely what the
# actual build needs -- not a guessed subset.
print_libreboot_apt_hint() {
    local distro="$1"
    local dep_file="$LIBREBOOT_DIR/config/dependencies/$distro"
    if [[ ! -f "$dep_file" ]]; then
        log_warn "Cannot read lbmk's own dependency list ($dep_file not found yet -- clone libreboot first)."
        return 1
    fi
    local pkg_add pkglist
    # shellcheck disable=SC1090
    pkg_add="" pkglist=""
    source "$dep_file"
    log_info "libreboot build dependencies (from lbmk's own config/dependencies/$distro):"
    printf '    sudo %s %s\n' "$pkg_add" "$pkglist"
}

detect_distro() {
    local os_id="" os_like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="${ID:-}"; os_like="${ID_LIKE:-}"
    fi
    case "$os_id" in
        ubuntu) echo "ubuntu" ;;
        debian) echo "debian" ;;
        *)
            case "$os_like" in
                *ubuntu*) echo "ubuntu" ;;
                *debian*) echo "debian" ;;
                *) echo "debian" ;;
            esac
            ;;
    esac
}

#!/usr/bin/env bash
# Integration with the real libreboot build system (`lbmk`).
#
# Every command used here was verified by reading the actual lbmk source
# (codeberg.org/libreboot/lbmk) rather than assumed from documentation
# prose -- see README "Grounded in real Libreboot source" for the specific
# files/lines each command comes from. In particular:
#
#   ./mk dependencies <distro>   -- include/init.sh xbmk_init(), reads
#                                    config/dependencies/<distro>
#   ./mk -b coreboot list        -- include/tree.sh build_targets(),
#                                    the literal string "list" triggers
#                                    `ls -1 config/coreboot`
#   ./mk -b coreboot <target>    -- include/tree.sh trees()/build_targets()
#
# T440p vendor ME/GbE/descriptor files are NOT something this tool needs to
# splice in manually: lbmk ships a redistributable IFD+GbE template for
# this board (config/ifd/t440p/{ifd,gbe} in the cloned tree) and downloads
# Intel ME directly from Lenovo's official update server at build time
# (config/vendor/haswell/pkg.cfg, pinned by SHA512 in that same file). A
# plain `./mk -b coreboot <target>` therefore produces a complete, working
# ROM on its own. The user's verified dumps are used only to preserve
# their own original GbE MAC address (see inject_original_mac below) --
# an optional personalization, not a build requirement.

LIBREBOOT_DIR="$ROOT_DIR/libreboot"

prepare_libreboot() {
    if [[ ! -d "$LIBREBOOT_DIR/.git" ]]; then
        log_info "Cloning lbmk ($LIBREBOOT_GIT_URL) ..."
        git clone --depth 1 "$LIBREBOOT_GIT_URL" "$LIBREBOOT_DIR" \
            >>"$LOG_FILE" 2>&1 || die "ERROR: Libreboot source verification failed." \
                "Could not clone $LIBREBOOT_GIT_URL" "STOP."
    else
        log_info "Reusing existing clone at $LIBREBOOT_DIR"
    fi

    local want_ref="$LIBREBOOT_VERSION"
    [[ "$want_ref" == "recommended" ]] && want_ref="$LIBREBOOT_RECOMMENDED_COMMIT"

    (
        cd "$LIBREBOOT_DIR" || exit 1
        local head
        head=$(git rev-parse HEAD)
        if [[ "$head" != "$want_ref"* ]]; then
            log_info "Fetching full history to check out $want_ref ..."
            git fetch --unshallow >>"$LOG_FILE" 2>&1 || \
                git fetch --all >>"$LOG_FILE" 2>&1
            git checkout "$want_ref" >>"$LOG_FILE" 2>&1 || \
                exit 1
        fi
    ) || die "ERROR: Libreboot source verification failed." \
             "Could not check out ref '$want_ref' in $LIBREBOOT_DIR" "STOP."

    local commit
    commit=$(cd "$LIBREBOOT_DIR" && git rev-parse HEAD)
    log_ok "Libreboot source (lbmk @ ${commit:0:12})"
    LBMK_COMMIT="$commit"
}

# discover_target NAME_HINT -- confirms a target actually exists in the
# cloned tree via the real `list` command, instead of trusting a hardcoded
# string. Dies loudly if it's gone (e.g. a future lbmk release renamed or
# dropped the board) rather than silently building the wrong thing.
discover_target() {
    local hint="$1"
    local listing
    listing=$(cd "$LIBREBOOT_DIR" && ./mk -b coreboot list 2>>"$LOG_FILE")
    if ! grep -qx "$hint" <<<"$listing"; then
        die "ERROR: Libreboot source verification failed." \
            "Expected coreboot target '$hint' not found in this lbmk checkout." \
            "Available t440p-related targets:" \
            "$(grep -i t440p <<<"$listing")" \
            "STOP."
    fi
    printf '%s' "$hint"
}

print_dependency_command() {
    local distro
    distro=$(detect_distro)
    print_libreboot_apt_hint "$distro"
}

# build_target TARGET -- runs the real build and returns the produced ROM
# path via stdout. Fails loudly (spec: never call a partial build a
# success) if no .rom file appears.
build_target() {
    local target="$1"
    log_info "Building $target (this can take a long time on first run -- crossgcc toolchains + coreboot are being compiled) ..."

    (
        cd "$LIBREBOOT_DIR" || exit 1
        ./mk -b coreboot "$target"
    ) >>"$LOG_FILE" 2>&1
    local status=$?

    if [[ $status -ne 0 ]]; then
        die "ERROR: GRUB2 payload configuration failed." \
            "'./mk -b coreboot $target' exited with status $status." \
            "See $LOG_FILE for the full build log." \
            "STOP."
    fi

    local rom
    rom=$(find "$LIBREBOOT_DIR/bin/$target" -maxdepth 1 -name '*.rom' ! -name '*_txtmode.rom' 2>/dev/null | sort | head -n1)
    if [[ -z "$rom" ]]; then
        # fall back to any rom at all (e.g. a txtmode-only variant)
        rom=$(find "$LIBREBOOT_DIR/bin/$target" -maxdepth 1 -name '*.rom' 2>/dev/null | sort | head -n1)
    fi
    if [[ -z "$rom" || ! -f "$rom" ]]; then
        die "ERROR: Final ROM verification failed." \
            "Build reported success but no .rom file was found under bin/$target/." \
            "STOP."
    fi
    log_ok "ROM build ($target -> $(basename "$rom"))"
    printf '%s' "$rom"
}

# inject_original_mac ROM_PATH -- writes the GbE MAC address found in the
# user's own verified dumps into the freshly built ROM, mirroring lbmk's
# own documented mechanism (include/inject.sh modify_mac()/newmac(): copy
# the GbE region to a temp file, set the MAC with nvmutil, write it back
# with `ifdtool -i GbE:<file> <rom> -O <rom>`). Applied directly to our own
# build output rather than through lbmk's release/tar.xz packaging, since
# that pipeline is meant for official multi-board release archives.
#
# Best-effort: a failure here is reported as a WARNING, not a build
# failure, since the ROM produced by build_target() is already complete
# and flashable without it.
inject_original_mac() {
    local rom="$1"
    local tree="default"
    local ifdtool="$LIBREBOOT_DIR/elf/coreboot/$tree/ifdtool"
    local nvmutil="$LIBREBOOT_DIR/util/nvmutil/nvmutil"

    if [[ ! -x "$ifdtool" ]]; then
        log_warn "ifdtool not found at $ifdtool -- skipping MAC preservation."
        return 0
    fi

    make -C "$LIBREBOOT_DIR/util/nvmutil" >>"$LOG_FILE" 2>&1 || {
        log_warn "Could not build nvmutil -- skipping MAC preservation."
        return 0
    }

    local extract_dir="$WORK_BUILD_DIR/ifd_extract"
    rm -rf "$extract_dir"; mkdir -p "$extract_dir"

    ( cd "$extract_dir" && "$ifdtool" -x "$VENDOR_ROM" ) >>"$LOG_FILE" 2>&1
    local gbe_file
    gbe_file=$(find "$extract_dir" -iname '*gbe*' -type f | head -n1)
    if [[ -z "$gbe_file" ]]; then
        log_warn "Could not extract GbE region from vendor.rom -- skipping MAC preservation."
        return 0
    fi

    local mac
    mac=$("$nvmutil" "$gbe_file" dump 2>>"$LOG_FILE" | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -n1)
    if [[ -z "$mac" ]]; then
        log_warn "Could not read a MAC address from the dumped GbE region -- skipping MAC preservation."
        return 0
    fi

    "$nvmutil" "$gbe_file" setmac "$mac" >>"$LOG_FILE" 2>&1 || {
        log_warn "nvmutil setmac failed -- skipping MAC preservation."
        return 0
    }
    "$ifdtool" -i "GbE:$gbe_file" "$rom" -O "$rom" >>"$LOG_FILE" 2>&1 || {
        log_warn "ifdtool GbE injection failed -- skipping MAC preservation."
        return 0
    }

    ORIGINAL_MAC="$mac"
    log_ok "Preserved original GbE MAC address ($mac)"
}

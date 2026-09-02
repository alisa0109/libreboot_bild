#!/usr/bin/env bash
# GRUB2 payload configuration: background image + config knobs (spec
# sections 10-11).
#
# Grounded in the real lbmk source:
#   - background image file: config/data/grub/background/background1280x800.png
#     (1280x800, 8-bit palette PNG), injected into CBFS as raw file
#     "background.png" ONLY for the graphical/libgfxinit build variant
#     (include/rom.sh add_grub(), condition: initmode != normal AND
#     displaymode != txtmode). We select that variant's .rom in
#     lib/libreboot.sh build_target().
#   - GRUB script (compiled into the payload's core.img) lives at
#     config/grub/default/config/payload -- a plain-text GRUB script we can
#     edit directly before the build (timeout/default entry).
#   - keymaps: pre-built .gkb files under config/data/grub/keymap/*.gkb are
#     auto-embedded by mkseagrub(); GRUB_KEYMAP just needs to name one that
#     already exists there (e.g. "usqwerty").

PREPARE_BG_PY="$ROOT_DIR/tools/prepare_background.py"

validate_background() {
    local src="$ROOT_DIR/$GRUB_BACKGROUND"
    if [[ ! -f "$src" ]]; then
        log_warn "No background image at $GRUB_BACKGROUND -- keeping libreboot's default background."
        HAVE_CUSTOM_BACKGROUND="false"
        return 0
    fi

    local ftype
    ftype=$(file -b --mime-type "$src")
    case "$ftype" in
        image/png|image/jpeg) : ;;
        *)
            die "ERROR: GRUB background image is invalid." \
                "$src has MIME type '$ftype', expected image/png or image/jpeg." \
                "STOP."
            ;;
    esac
    log_ok "Background image format ($ftype)"
    HAVE_CUSTOM_BACKGROUND="true"
}

convert_background() {
    [[ "$HAVE_CUSTOM_BACKGROUND" == "true" ]] || return 0
    mkdir -p "$WORK_BUILD_DIR"
    local src="$ROOT_DIR/$GRUB_BACKGROUND"
    local dst="$WORK_BUILD_DIR/background1280x800.png"
    local out
    if ! out=$(python3 "$PREPARE_BG_PY" "$src" "$dst" 2>&1); then
        die "ERROR: GRUB background image is invalid." "$out" "STOP."
    fi
    _log_line "$out"
    log_ok "Background image converted (1280x800)"
    CONVERTED_BACKGROUND="$dst"
}

apply_background() {
    [[ "$HAVE_CUSTOM_BACKGROUND" == "true" ]] || return 0
    local target_path="$LIBREBOOT_DIR/config/data/grub/background/background1280x800.png"
    cp "$CONVERTED_BACKGROUND" "$target_path" || \
        die "ERROR: GRUB2 payload configuration failed." \
            "Could not install background image to $target_path" "STOP."
    log_ok "Background image installed into GRUB payload source tree"
}

apply_grub_config() {
    local payload_cfg="$LIBREBOOT_DIR/config/grub/default/config/payload"
    [[ -f "$payload_cfg" ]] || \
        die "ERROR: GRUB2 payload configuration failed." \
            "$payload_cfg not found -- unexpected lbmk tree layout." "STOP."

    if [[ -n "${GRUB_TIMEOUT:-}" ]]; then
        # the default's "set timeout=8" line lives inside an else-branch
        # and is tab-indented -- match with leading whitespace preserved,
        # don't anchor on column 1.
        if ! grep -qE '^[[:blank:]]*set timeout=' "$payload_cfg"; then
            die "ERROR: GRUB2 payload configuration failed." \
                "No 'set timeout=' line found in $payload_cfg (unexpected lbmk tree layout)." "STOP."
        fi
        sed -i -E "s/^([[:blank:]]*)set timeout=.*/\1set timeout=${GRUB_TIMEOUT}/" "$payload_cfg" || \
            die "ERROR: GRUB2 payload configuration failed." "Could not set timeout." "STOP."
        log_ok "GRUB timeout = ${GRUB_TIMEOUT}s"
    fi

    if [[ -n "${GRUB_DEFAULT_ENTRY:-}" ]]; then
        if ! grep -qE '^[[:blank:]]*set default=' "$payload_cfg"; then
            die "ERROR: GRUB2 payload configuration failed." \
                "No 'set default=' line found in $payload_cfg (unexpected lbmk tree layout)." "STOP."
        fi
        sed -i -E "s/^([[:blank:]]*)set default=.*/\1set default=\"${GRUB_DEFAULT_ENTRY}\"/" "$payload_cfg" || \
            die "ERROR: GRUB2 payload configuration failed." "Could not set default entry." "STOP."
        log_ok "GRUB default entry = ${GRUB_DEFAULT_ENTRY}"
    fi

    if [[ -n "${GRUB_KEYMAP:-}" ]]; then
        local gkb="$LIBREBOOT_DIR/config/data/grub/keymap/${GRUB_KEYMAP}.gkb"
        if [[ -f "$gkb" ]]; then
            log_ok "GRUB keymap = ${GRUB_KEYMAP}"
        else
            log_warn "GRUB_KEYMAP='${GRUB_KEYMAP}' not found under config/data/grub/keymap/ -- ignoring (available: $(ls "$LIBREBOOT_DIR/config/data/grub/keymap" | sed 's/\.gkb$//' | tr '\n' ' '))"
        fi
    fi

    log_ok "GRUB2 configuration"
}

# verify_background_in_rom ROM_PATH -- confirms the background actually
# made it into the built ROM (spec 11.6/18), via the real cbfstool built
# alongside coreboot for this tree.
verify_background_in_rom() {
    [[ "$HAVE_CUSTOM_BACKGROUND" == "true" ]] || return 0
    local rom="$1"
    local cbfstool="$LIBREBOOT_DIR/elf/coreboot/default/cbfstool"
    if [[ ! -x "$cbfstool" ]]; then
        log_warn "cbfstool not found -- cannot verify background image presence in ROM."
        return 0
    fi
    if ! "$cbfstool" "$rom" print 2>>"$LOG_FILE" | grep -q 'background\.png'; then
        die "ERROR: Final ROM verification failed." \
            "background.png is not present in the built ROM's CBFS." \
            "STOP."
    fi
    log_ok "Background image present in ROM (CBFS)"
}

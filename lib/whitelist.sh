#!/usr/bin/env bash
# Wi-Fi whitelist handling (spec sections 9, 12).
#
# IMPORTANT CORRECTION vs. the original spec (documented in README): the
# Lenovo Wi-Fi whitelist is code that lives inside Lenovo's proprietary
# BIOS/UEFI. Libreboot does not contain that code at all -- it replaces
# the firmware entirely with coreboot + GRUB2. There is no `./mk` command,
# flag, or binary patch anywhere in lbmk that "removes" a whitelist,
# because there is nothing there to remove. Searching libreboot.org and
# doc.coreboot.org for this board turned up no such workflow.
#
# This module therefore does not patch anything. It verifies that the
# produced ROM is a genuine coreboot/libreboot build (i.e. actually free
# of the proprietary vendor firmware, which is what actually makes the
# whitelist absent) and records that fact for the report.

verify_whitelist_absent() {
    local rom="$1"
    [[ "${REMOVE_WIFI_WHITELIST:-true}" == "true" ]] || {
        log_info "Wi-Fi whitelist verification skipped (REMOVE_WIFI_WHITELIST=false in config)."
        return 0
    }

    if ! strings "$rom" 2>/dev/null | grep -qi 'coreboot'; then
        die "ERROR:" \
            "Wi-Fi whitelist modification is not supported by this Libreboot configuration." \
            "" \
            "The built ROM does not appear to contain a genuine coreboot build" \
            "(no 'coreboot' identification string found), so this tool cannot" \
            "confirm the vendor whitelist-enforcement code is actually absent." \
            "" \
            "STOP."
    fi

    log_ok "Wi-Fi whitelist configuration (inherently absent: genuine coreboot/libreboot build, no vendor BIOS code present)"
}

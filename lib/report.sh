#!/usr/bin/env bash
# BUILD-REPORT.txt + final summary banner (spec sections 23, 29).

write_report() {
    local report="$OUTPUT_DIR/BUILD-REPORT.txt"
    mkdir -p "$OUTPUT_DIR"

    {
        printf 'T440p Libreboot Build Report\n'
        printf '=============================\n\n'
        printf 'Model:            Lenovo ThinkPad T440p\n'
        printf 'Date:             %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        printf 'Payload:          GRUB2\n'
        printf 'Libreboot target: %s\n' "${BUILD_TARGET:-unknown}"
        printf 'lbmk git commit:  %s\n' "${LBMK_COMMIT:-unknown}"
        printf 'Wi-Fi whitelist:  ABSENT (genuine coreboot/libreboot build contains no vendor whitelist code)\n'
        printf 'GbE MAC address:  %s\n' "${ORIGINAL_MAC:-not preserved (see log)}"
        printf 'Background image: %s\n' "${HAVE_CUSTOM_BACKGROUND:-false}"
        printf '\n'
        printf 'Input dump hashes (SHA256)\n'
        printf -- '---------------------------\n'
        for key in "${!DUMP_SHA256[@]}"; do
            printf '%s  %s\n' "${DUMP_SHA256[$key]}" "$(basename "$key")"
        done | sort -k2
        printf '\n'
        printf 'Output ROM hashes (SHA256)\n'
        printf -- '---------------------------\n'
        [[ -n "${FINAL_ROM_FULL:-}" ]] && printf '%s  %s\n' "$(sha256_of "$FINAL_ROM_FULL")" "$(basename "$FINAL_ROM_FULL")"
        [[ -n "${FINAL_ROM_SPI1:-}" ]] && printf '%s  %s\n' "$(sha256_of "$FINAL_ROM_SPI1")" "$(basename "$FINAL_ROM_SPI1")"
        [[ -n "${FINAL_ROM_SPI2:-}" ]] && printf '%s  %s\n' "$(sha256_of "$FINAL_ROM_SPI2")" "$(basename "$FINAL_ROM_SPI2")"
        printf '\n'
        printf 'Reproducibility metadata\n'
        printf -- '--------------------------\n'
        printf 'uname -a:         %s\n' "$(uname -a)"
        printf 'Config snapshot:  %s\n' "$ROOT_DIR/config/t440p.conf"
        [[ "${HAVE_CUSTOM_BACKGROUND:-false}" == "true" ]] && \
            printf 'Background SHA256: %s\n' "$(sha256_of "$ROOT_DIR/$GRUB_BACKGROUND")"
        printf '\n'
        printf 'Build status:     SUCCESS\n'
    } > "$report"

    log_ok "Report written to $report"
}

print_success_banner() {
    cat <<EOF

========================================
BUILD SUCCESSFUL
========================================

Model:
Lenovo ThinkPad T440p

Payload:
GRUB2

Wi-Fi whitelist:
ABSENT (no vendor whitelist code present in a genuine libreboot build)

GRUB background:
$( [[ "${HAVE_CUSTOM_BACKGROUND:-false}" == "true" ]] && echo "INSTALLED" || echo "DEFAULT (no custom image supplied)" )

ROM (full, 12 MiB, for reference/hashing):
${FINAL_ROM_FULL:-}

ROM (flash into the 8 MiB base-cover chip):
${FINAL_ROM_SPI1:-}

ROM (flash into the 4 MiB door-accessible chip):
${FINAL_ROM_SPI2:-}

SHA256 (full ROM):
${FINAL_ROM_SHA256:-}

Report:
$OUTPUT_DIR/BUILD-REPORT.txt

========================================
This tool only BUILDS and VERIFIES firmware. It never writes to SPI flash.
Flashing is a separate, manual step -- verify the ROM yourself first.
========================================
EOF
}

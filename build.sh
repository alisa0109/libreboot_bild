#!/usr/bin/env bash
# T440p Libreboot Builder -- entrypoint.
#
# This tool only ever BUILDS and VERIFIES a libreboot ROM for the Lenovo
# ThinkPad T440p. It never writes to SPI flash. See README.md.
set -uo pipefail

SCRIPT_VERSION="1.0.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR

mkdir -p "$ROOT_DIR/logs"
LOG_FILE="$ROOT_DIR/logs/build-$(date -u '+%Y-%m-%d-%H%M%S').log"
export LOG_FILE
: > "$LOG_FILE"

# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/deps.sh
source "$ROOT_DIR/lib/deps.sh"
# shellcheck source=lib/dumps.sh
source "$ROOT_DIR/lib/dumps.sh"
# shellcheck source=lib/layout.sh
source "$ROOT_DIR/lib/layout.sh"
# shellcheck source=lib/libreboot.sh
source "$ROOT_DIR/lib/libreboot.sh"
# shellcheck source=lib/grub.sh
source "$ROOT_DIR/lib/grub.sh"
# shellcheck source=lib/whitelist.sh
source "$ROOT_DIR/lib/whitelist.sh"
# shellcheck source=lib/rom_verify.sh
source "$ROOT_DIR/lib/rom_verify.sh"
# shellcheck source=lib/report.sh
source "$ROOT_DIR/lib/report.sh"

CONFIG_FILE="$ROOT_DIR/config/t440p.conf"
[[ -f "$CONFIG_FILE" ]] || die "ERROR: Missing $CONFIG_FILE. STOP."
# shellcheck source=config/t440p.conf
source "$CONFIG_FILE"

_log_line "T440p Libreboot Builder v$SCRIPT_VERSION"
_log_line "uname -a: $(uname -a)"

print_banner() {
    cat <<'EOF'
========================================
ThinkPad T440p Libreboot Builder
========================================

[1] Check dependencies
[2] Verify BIOS dumps
[3] Prepare Libreboot
[4] Configure GRUB2
[5] Configure Wi-Fi whitelist
[6] Build ROM
[7] Verify ROM
[8] Create report

Running in fully automatic mode (default). Use --help to see other modes.
EOF
}

print_help() {
    cat <<EOF
T440p Libreboot Builder v$SCRIPT_VERSION

Usage: ./build.sh [OPTION]

  (no option)      Show the menu banner, then run the full automatic workflow
  --auto           Run the full automatic workflow (dumps -> ROM -> report)
  --check          Dry run: verify OS/deps/dumps/hashes/sizes/background/config,
                   create nothing
  --verify-dumps   Only verify the 4 BIOS dump files in dumps/
  --prepare        Verify dumps + clone/checkout libreboot source
  --build          Run the full build (implies verify-dumps + prepare)
  --verify         Re-run final verification against an existing output ROM
  --clean          Remove work/ and libreboot build artifacts (never touches
                   dumps/ or assets/)
  --help           Show this help
EOF
}

stage_deps() {
    log_info "[1/8] Checking dependencies"
    check_wrapper_deps || { [[ "$1" == "soft" ]] || exit 1; }
}

stage_verify_dumps() {
    log_info "[2/8] Verifying BIOS dumps"
    verify_dumps
    verify_t440p_layout
}

stage_prepare() {
    log_info "[3/8] Preparing Libreboot"
    prepare_libreboot
    print_dependency_command
    BUILD_TARGET=$(discover_target "$LIBREBOOT_TARGET_FULL")
}

stage_grub() {
    log_info "[4/8] Configuring GRUB2"
    validate_background
    convert_background
}

run_check() {
    check_os
    stage_deps soft
    stage_verify_dumps
    stage_prepare
    stage_grub
    log_ok "Dry run complete -- no ROM was built, output/ was not touched."
}

run_auto() {
    check_os
    stage_deps hard
    stage_verify_dumps
    merge_dumps
    stage_prepare
    stage_grub
    apply_background
    apply_grub_config

    log_info "[5/8] Wi-Fi whitelist (see README correction: nothing to patch)"

    log_info "[6/8] Building ROM"
    local rom
    rom=$(build_target "$BUILD_TARGET")

    if [[ "${PRESERVE_ORIGINAL_MAC:-true}" == "true" ]]; then
        inject_original_mac "$rom"
    fi

    log_info "[7/8] Verifying ROM"
    verify_whitelist_absent "$rom"
    verify_background_in_rom "$rom"
    verify_and_stage_rom "$rom"

    log_info "[8/8] Creating report"
    write_report
    print_success_banner
}

run_clean() {
    log_info "Cleaning work/ and libreboot build artifacts (dumps/ and assets/ are never touched)"
    rm -rf "$ROOT_DIR/work"
    mkdir -p "$ROOT_DIR/work/original" "$ROOT_DIR/work/modified" "$ROOT_DIR/work/build" "$ROOT_DIR/work/backup"
    if [[ -d "$ROOT_DIR/libreboot/.git" ]]; then
        (cd "$ROOT_DIR/libreboot" && git clean -xdf >>"$LOG_FILE" 2>&1 && git checkout -- . >>"$LOG_FILE" 2>&1) || true
    fi
    log_ok "Clean complete"
}

main() {
    local mode="${1:-}"
    case "$mode" in
        --help|-h) print_help; exit 0 ;;
        --check) run_check ;;
        --verify-dumps) check_os; stage_verify_dumps ;;
        --prepare) check_os; stage_deps soft; stage_verify_dumps; stage_prepare ;;
        --build|--auto) print_banner; run_auto ;;
        --verify)
            check_os
            [[ -f "$ROOT_DIR/output/t440p-libreboot.rom" ]] || \
                die "ERROR: No output/t440p-libreboot.rom to verify. Run --auto first. STOP."
            prepare_libreboot
            BUILD_TARGET=$(discover_target "$LIBREBOOT_TARGET_FULL")
            verify_whitelist_absent "$ROOT_DIR/output/t440p-libreboot.rom"
            verify_and_stage_rom "$ROOT_DIR/output/t440p-libreboot.rom"
            ;;
        --clean) run_clean ;;
        "") print_banner; run_auto ;;
        *) log_err "Unknown option: $mode"; print_help; exit 1 ;;
    esac
}

main "$@"

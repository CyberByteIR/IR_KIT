#!/usr/bin/env bash

# Mac Incident Response Script
# By Jeremy Brice
# dfir@cyberbyteir.com
# Updated: 2026-11-12

# -e is deliberately not set: a failed collector is logged and skipped, it must not abort the run
set -uo pipefail

# Configuration Variables
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
UAC_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/uac/uac"
FUJI_PATH="$SCRIPT_DIR/TOOLS/FS_Acquisition/Fuji/FujiApp.dmg"
OUTPUT_DIR="$SCRIPT_DIR/$(hostname)"
LOG_FILE="$OUTPUT_DIR/log.txt"
ISSUES=0
FAILURES=0


# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Create output directory
if ! mkdir -p "$OUTPUT_DIR"; then
    echo "Error: cannot create output directory $OUTPUT_DIR"
    exit 1
fi
if ! : >> "$LOG_FILE"; then
    echo "Error: cannot write to $LOG_FILE"
    exit 1
fi

# Current time, UTC, ISO-8601
ts() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Timestamped entry to the console and log.txt; FAILED/WARNING/SKIPPED entries are counted
log() {
    local line
    line="$(ts): $1"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
    case "$1" in
        FAILED*|SKIPPED*)
            ISSUES=$((ISSUES + 1))
            FAILURES=$((FAILURES + 1))
            ;;
        WARNING*)
            ISSUES=$((ISSUES + 1))
            ;;
    esac
}

# collect <output file> <label> <command...>
# Appends the command's stdout and stderr to the file; a non-zero exit is logged
collect() {
    local out_file="$1" label="$2" rc=0
    shift 2
    echo "$label:" >> "$out_file"
    "$@" >> "$out_file" 2>&1 || rc=$?
    if (( rc != 0 )); then
        log "WARNING: '$*' returned exit code $rc - review $(basename "$out_file")"
    fi
}

# Host, account, system clock and time zone, recorded before anything is collected
log_run_header() {
    local tz_name
    tz_name="$(readlink /etc/localtime 2> /dev/null)"
    tz_name="${tz_name##*zoneinfo/}"

    {
        echo "==== IR Kit mac_IR.sh ===="
        echo "Hostname                 : $(hostname)"
        echo "Script                   : $SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
        echo "Running as               : $(id -un) (uid $EUID)${SUDO_USER:+, via sudo from $SUDO_USER}"
        echo "Console user             : $(stat -f%Su /dev/console 2>&1)"
        echo "Collection started (UTC) : $(ts)"
        echo "System clock (local)     : $(date +"%Y-%m-%dT%H:%M:%S%z")"
        echo "Time zone                : ${tz_name:-unknown} ($(date +%Z), UTC offset $(date +%z))"
        echo "Last boot                : $(sysctl -n kern.boottime 2>&1)"
        echo "Network time             : $(systemsetup -getusingnetworktime 2>&1)"
        echo "NOTE: Compare the system clock above with a trusted time source and record any offset."
        echo "Log entries below are stamped in UTC."
    } | tee -a "$LOG_FILE"
}

# Full Disk Access - without it TCC-protected data is silently left out of the collection
check_full_disk_access() {
    local tcc_db="/Library/Application Support/com.apple.TCC/TCC.db"

    if head -c 1 "$tcc_db" > /dev/null 2>&1; then
        log "Full Disk Access check passed"
        return 0
    fi
    log "WARNING: Full Disk Access check failed - cannot read $tcc_db. Grant Full Disk Access to the terminal application, otherwise TCC-protected data will be missing"
    echo "Press Enter to continue without Full Disk Access, or Ctrl-C to abort..."
    read -r
}

# System Info
log_system_info() {
    local info_file="$OUTPUT_DIR/system_info.txt"

    log "Started System Information acquisition"

    {
        echo "Hostname: $(hostname)"
        echo "macOS Version: $(sw_vers -productVersion)"
        echo "Kernel: $(uname -v)"
        echo "Architecture: $(uname -m)"
        echo "Total Memory: $(sysctl -n hw.memsize) bytes"
    } > "$info_file" 2>&1
    collect "$info_file" "Memory Usage Before Capture" vm_stat
    collect "$info_file" "Disk Space" df -h
    collect "$info_file" "Network interfaces" ifconfig
    collect "$info_file" "System Profile" system_profiler -detailLevel mini

    log "Completed System Information acquisition"
}

# UAC
acquire_uac() {
    mkdir -p "$OUTPUT_DIR/uac"
    local rc=0
    log "Started UAC acquisition"
    echo "Output directory: $OUTPUT_DIR/uac"

    "$UAC_PATH" -p ir_triage "$OUTPUT_DIR/uac" || rc=$?
    if (( rc != 0 )); then
        log "FAILED: UAC acquisition - uac exit code $rc"
        return 1
    fi
    if [[ -z "$(ls -A "$OUTPUT_DIR/uac" 2> /dev/null)" ]]; then
        log "FAILED: UAC acquisition - uac exit code 0 but no output in $OUTPUT_DIR/uac"
        return 1
    fi

    log "Completed UAC acquisition"
}

# Fuji
acquire_fuji() {
    mkdir -p "$OUTPUT_DIR/fuji"
    local rc=0
    log "Started Fuji acquisition"
    echo "Save the Fuji image to: $OUTPUT_DIR/fuji"

    open "$FUJI_PATH" || rc=$?
    if (( rc != 0 )); then
        log "FAILED: Fuji acquisition - could not open $FUJI_PATH, exit code $rc"
        return 1
    fi
    echo "The Fuji disk image has been opened. Start Fuji from the mounted volume if it is not already running."
    echo "Complete the acquisition manually, then press Enter to continue..."
    read -r

    # Fuji is driven by hand, so the script can only check that something was written
    if [[ -z "$(ls -A "$OUTPUT_DIR/fuji" 2> /dev/null)" ]]; then
        log "WARNING: Fuji acquisition ended by operator but $OUTPUT_DIR/fuji is empty - confirm where the image was saved"
        return 0
    fi
    log "Completed Fuji acquisition - ended by operator, output present in $OUTPUT_DIR/fuji"
}

# Main execution
main() {

    log_run_header
    check_full_disk_access

    # Log system information
    log_system_info

    # Perform UAC acquisition; a missing tool must not stop the Fuji acquisition
    if [[ -x "$UAC_PATH" ]]; then
        acquire_uac
    else
        log "SKIPPED: UAC acquisition - UAC not found or not executable at $UAC_PATH"
    fi

    # Perform fuji acquisition
    if [[ -f "$FUJI_PATH" ]]; then
        acquire_fuji
    else
        log "SKIPPED: Fuji acquisition - disk image not found at $FUJI_PATH"
    fi

    log "Completed Acquisition - $ISSUES FAILED/WARNING/SKIPPED entries, review $LOG_FILE"
    if (( FAILURES > 0 )); then
        return 1
    fi
}

# Trap to handle interruptions
trap 'log "FAILED: Acquisition interrupted by signal"; exit 1' SIGINT SIGTERM

# Run the main function
main

#!/usr/bin/env bash

# Linux Incident Response Script
# By Jeremy Brice
# dfir@cyberbyteir.com
# Updated: 2026-11-12

# -e is deliberately not set: a failed collector is logged and skipped, it must not abort the run
set -uo pipefail

# Configuration Variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
#echo "Script directory: $SCRIPT_DIR"
AVML_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/avml/avml"
#echo "AVML path: $AVML_PATH"
UAC_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/uac/uac"
#echo "UAC path: $UAC_PATH"
OUTPUT_DIR="$SCRIPT_DIR/$(hostname)"
#echo "Output directory: $OUTPUT_DIR"
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

# Function / host, account, system clock and time zone, recorded before anything is collected
log_run_header() {
    local tz_name boot_time
    tz_name="$(readlink /etc/localtime 2> /dev/null)"
    tz_name="${tz_name##*zoneinfo/}"
    if [[ -z "$tz_name" && -r /etc/timezone ]]; then
        tz_name="$(cat /etc/timezone)"
    fi
    boot_time="$(uptime -s 2> /dev/null || who -b 2> /dev/null | awk '{print $3, $4}')"

    {
        echo "==== IR Kit lin_IR.sh ===="
        echo "Hostname                 : $(hostname)"
        echo "Script                   : $(readlink -f "$0")"
        echo "Running as               : $(id -un) (uid $EUID)${SUDO_USER:+, via sudo from $SUDO_USER}"
        echo "Collection started (UTC) : $(ts)"
        echo "System clock (local)     : $(date +"%Y-%m-%dT%H:%M:%S%z")"
        echo "Time zone                : ${tz_name:-unknown} ($(date +%Z), UTC offset $(date +%z))"
        echo "Last boot (local)        : ${boot_time:-unknown}"
        if command -v timedatectl > /dev/null 2>&1; then
            echo "timedatectl:"
            timedatectl 2>&1
        fi
        echo "NOTE: Compare the system clock above with a trusted time source and record any offset."
        echo "Log entries below are stamped in UTC."
    } | tee -a "$LOG_FILE"
}

# Function / memory acquisition
acquire_memory() {
    mkdir -p "$OUTPUT_DIR/avml"
    local avml_output_file="$OUTPUT_DIR/avml/mem.lime" rc=0
    log "Started Memory acquisition"
    echo "Output file: $avml_output_file"

    "$AVML_PATH" --compress "$avml_output_file" || rc=$?
    if (( rc != 0 )); then
        log "FAILED: Memory acquisition - avml exit code $rc"
        return 1
    fi
    if [[ ! -s "$avml_output_file" ]]; then
        log "FAILED: Memory acquisition - avml exit code 0 but no image written to $avml_output_file"
        return 1
    fi
    log "Completed Memory acquisition - avml --compress, $(wc -c < "$avml_output_file" | tr -d ' ') bytes"
}

# Function / system information
log_system_info() {
    local info_file="$OUTPUT_DIR/system_info.txt"

    log "Started System Information acquisition"

    {
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Total Memory: $(LC_ALL=C free -h | awk '/^Mem:/ {print $2}')"
    } > "$info_file" 2>&1
    collect "$info_file" "Memory Usage Before Capture" free -h
    collect "$info_file" "Disk Space" df -h
    collect "$info_file" "Network interfaces" ip addr
    collect "$info_file" "System info" uname -a

    log "Completed System Information acquisition"
}

# Function / live response data
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

# Main execution
main() {

    log_run_header

    # Log system information
    log_system_info

    # Perform memory acquisition; a missing tool must not stop the UAC collection
    if [[ -x "$AVML_PATH" ]]; then
        acquire_memory
    else
        log "SKIPPED: Memory acquisition - AVML not found or not executable at $AVML_PATH"
    fi

    # Perform UAC acquisition
    if [[ -x "$UAC_PATH" ]]; then
        acquire_uac
    else
        log "SKIPPED: UAC acquisition - UAC not found or not executable at $UAC_PATH"
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

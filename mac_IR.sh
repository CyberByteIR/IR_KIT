#!/bin/bash

# Mac Incident Response Script
# By Jeremy Brice
# forensics@cyberbyteconsulting.com
# Updated: 2026-05-26

# Configuration Variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
UAC_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/uac/uac"
FUJI_PATH="$SCRIPT_DIR/TOOLS/FS_Acquisition/Fuji/FujiApp.dmg"
OUTPUT_DIR="$SCRIPT_DIR/$(hostname)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")


# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# System Info
log_system_info() {
    local log_file="$OUTPUT_DIR/system_info.txt"

echo "$timestamp: Started System Information acquisition"
	echo "$timestamp: Started System Information acquisition" >> "$OUTPUT_DIR/log.txt"	

    {
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Total Memory: $(free -h | grep Mem: | awk '{print $2}')"
        echo "Memory Usage Before Capture:"
        free -h
        echo "Disk Space:"
        df -h
		echo "Minidump info: $(ifconfig, uname –a, system_profiler –detailLevel mini)"
    } > "$log_file"

   echo "$timestamp: Completed System Information acquisition"
	echo "$timestamp: Completed System Information acquisition" >> "$OUTPUT_DIR/log.txt"
}
# UAC
acquire_uac() {
	mkdir -p "$OUTPUT_DIR/uac"
    echo "$timestamp: Started UAC acquisition"
	echo "$timestamp: Started UAC acquisition" >> "$OUTPUT_DIR/log.txt"
    echo "Output directory: $OUTPUT_DIR/uac"

    if ! "$UAC_PATH" -p ir_triage "$OUTPUT_DIR/uac"; then
        echo "Error: UAC acquisition failed"
        return 1
    fi

    echo "$timestamp: Completed UAC acquisition"
	echo "$timestamp: Completed UAC acquisition" >> "$OUTPUT_DIR/log.txt"
	
# Fuji
acquire_fuji() {
	mkdir -p "$OUTPUT_DIR/fuji"
    echo "$timestamp: Started Fuji acquisition"
	echo "$timestamp: Started Fuji acquisition" >> "$OUTPUT_DIR/log.txt"
    echo "Output file: $fuji_output_file"

    open "$FUJI_PATH"
    echo "Fuji has been launched. Complete the acquisition manually, then press Enter to continue..."
    read -r

    echo "$timestamp: Completed Fuji acquisition"
	echo "$timestamp: Completed Fuji acquisition" >> "$OUTPUT_DIR/log.txt"

	
# Main execution
main() {

    # Log system information
    log_system_info
	
	# Validate UAC path
    if [[ ! -x "$UAC_PATH" ]]; then
        echo "Error: UAC not found at $UAC_PATH"
        echo "Please check the UAC path and ensure it's executable"
        return 1
    fi
	# Perform UAC acquisition
	acquire_uac
	
	# Validate Fuji path
    if [[ ! -x "$FUJI_PATH" ]]; then
        echo "Error: Fuji not found at $FUJI_PATH"
        echo "Please check the Fuji path and ensure it's executable"
        return 1
    fi
	# Perform fuji acquisition
	acquire_fuji
echo "$timestamp: Completed Acquisition, review above output for errors"
echo "$timestamp: Completed Acquisition" >> "$OUTPUT_DIR/log.txt"
}

# Trap to handle interruptions
trap 'echo "Acquisition interrupted"; exit 1' SIGINT SIGTERM

# Run the main function
main

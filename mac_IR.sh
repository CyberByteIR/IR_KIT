#!/bin/bash

# Mac Incident Response Script
# By Jeremy Brice
# forensics@cyberbyteconsulting.com
# Updated: 2026-05-26

# Configuration Variables
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
UAC_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/uac/uac"
FUJI_PATH="$SCRIPT_DIR/TOOLS/FS_Acquisition/Fuji/FujiApp.dmg"
OUTPUT_DIR="$SCRIPT_DIR/$(hostname)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")


# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# System Info
log_system_info() {
    local log_file="$OUTPUT_DIR/system_info.txt"

	echo "$TIMESTAMP: Started System Information acquisition"
	echo "$TIMESTAMP: Started System Information acquisition" >> "$OUTPUT_DIR/log.txt"	

    {
        echo "Hostname: $(hostname)"
		echo "macOS Version: $(sw_vers -productVersion)"
        echo "Kernel: $(uname -v)"
        echo "Architecture: $(uname -m)"
        echo "Total Memory: $(sysctl -n hw.memsize) bytes"
        echo "Memory Usage Before Capture:"
        vm_stat
        echo "Disk Space:"
        df -h
		echo "Network interfaces:"
		ifconfig
		echo "System Profile:"
		system_profiler -detailLevel mini
    } > "$log_file"

   echo "$TIMESTAMP: Completed System Information acquisition"
	echo "$TIMESTAMP: Completed System Information acquisition" >> "$OUTPUT_DIR/log.txt"
}
# UAC
acquire_uac() {
	mkdir -p "$OUTPUT_DIR/uac"
    echo "$TIMESTAMP: Started UAC acquisition"
	echo "$TIMESTAMP: Started UAC acquisition" >> "$OUTPUT_DIR/log.txt"
    echo "Output directory: $OUTPUT_DIR/uac"

    if ! "$UAC_PATH" -p ir_triage "$OUTPUT_DIR/uac"; then
        echo "Error: UAC acquisition failed"
        return 1
    fi

    echo "$TIMESTAMP: Completed UAC acquisition"
	echo "$TIMESTAMP: Completed UAC acquisition" >> "$OUTPUT_DIR/log.txt"
	}
# Fuji
acquire_fuji() {
	mkdir -p "$OUTPUT_DIR/fuji"
    echo "$TIMESTAMP: Started Fuji acquisition"
	echo "$TIMESTAMP: Started Fuji acquisition" >> "$OUTPUT_DIR/log.txt"
    echo "Output file: $fuji_output_file"

    open "$FUJI_PATH"
    echo "Fuji has been launched. Complete the acquisition manually, then press Enter to continue..."
    read -r

    echo "$TIMESTAMP: Completed Fuji acquisition"
	echo "$TIMESTAMP: Completed Fuji acquisition" >> "$OUTPUT_DIR/log.txt"
}
	
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
    if [[ ! -f "$FUJI_PATH" ]]; then
        echo "Error: Fuji not found at $FUJI_PATH"
        echo "Please check the Fuji path and ensure it's executable"
        return 1
    fi
	# Perform fuji acquisition
	acquire_fuji
echo "$TIMESTAMP: Completed Acquisition, review above output for errors"
echo "$TIMESTAMP: Completed Acquisition" >> "$OUTPUT_DIR/log.txt"
}

# Trap to handle interruptions
trap 'echo "Acquisition interrupted"; exit 1' SIGINT SIGTERM

# Run the main function
main

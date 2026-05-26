#!/bin/bash

# Linux Incident Response Script
# By Jeremy Brice
# forensics@cyberbyteconsulting.com
# Updated: 2026-05-26

# Configuration Variables
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
#echo "Script directory: $SCRIPT_DIR"
AVML_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/avml/avml"
#echo "AVML path: $AVML_PATH"
UAC_PATH="$SCRIPT_DIR/TOOLS/Vol_Acquisition/uac/uac"
#echo "UAC path: $UAC_PATH"
OUTPUT_DIR="$SCRIPT_DIR/$(hostname)"
#echo "Output directory: $OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
#echo "Timestamp: $TIMESTAMP"

# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi


# Function / memory acquisition
acquire_memory() {
	mkdir -p "$OUTPUT_DIR/avml"
    local avml_output_file="$OUTPUT_DIR/avml/mem.lime"
    echo "$timestamp: Started Memory acquisition"
	echo "$timestamp: Started Memory acquisition" >> "$OUTPUT_DIR/log.txt"
    echo "Output file: $avml_output_file"

    if ! "$AVML_PATH" --compress "$avml_output_file"; then
        echo "Error: Memory acquisition failed"
        return 1
    fi
    echo "$timestamp: Completed Memory acquisition"
	echo "$timestamp: Completed Memory acquisition" >> "$OUTPUT_DIR/log.txt"

}

# Function / system information
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

# Function / live response data
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
	
# Main execution
main() {

    # Log system information
    log_system_info

    # Validate AVML path
    if [[ ! -x "$AVML_PATH" ]]; then
        echo "Error: AVML not found at $AVML_PATH"
        echo "Please check the AVML path and ensure it's executable"
        return 1
    fi

    # Perform memory acquisition
    acquire_memory

	# Validate UAC path
    if [[ ! -x "$UAC_PATH" ]]; then
        echo "Error: UAC not found at $UAC_PATH"
        echo "Please check the UAC path and ensure it's executable"
        return 1
    fi

	# Perform UAC acquisition
	acquire_uac
	

echo "$timestamp: Completed Acquisition, review above output for errors"
echo "$timestamp: Completed Acquisition" >> "$OUTPUT_DIR/log.txt"
}

# Trap to handle interruptions
trap 'echo "Acquisition interrupted"; exit 1' SIGINT SIGTERM

# Run the main function
main

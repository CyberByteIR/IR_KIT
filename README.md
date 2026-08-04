# IR_KIT - Incident Response Toolkit

**Author:** Jeremy Brice - Cyberbyte Consulting  
**Contact:** forensics@cyberbyteconsulting.com  
**Website:** https://cyberbyteconsulting.com  
**Last Updated:** 2026-08-04  
**Version:** v2.4.1  
**License:** MIT (scripts only - see LICENSE)

---

## Overview

IR_KIT is a portable incident response toolkit designed for rapid deployment during cybersecurity incidents. It provides automated collection scripts for Windows, Linux, and macOS systems, orchestrating multiple forensic tools to acquire memory, volatile data, filesystem images, and live triage results.

## Supported Platforms

- **Windows** (`win_IR.bat`) - Full-featured collection including memory, volatile data, artifact triage, and filesystem imaging
- **Windows, user context** (`win_clip_history.bat`) - Companion script for clipboard history; run in the subject user's own session
- **Linux** (`lin_IR.sh`) - Memory acquisition, system information, and artifact collection
- **macOS** (`mac_IR.sh`) - System information, artifact collection, and filesystem acquisition

## Directory Structure

```
IR_KIT/
├── win_IR.bat                  # Windows IR collection script
├── win_clip_history.bat        # Windows clipboard history (user context)
├── lin_IR.sh                   # Linux IR collection script
├── mac_IR.sh                   # macOS IR collection script
├── terminal.bat                # Portable Windows Terminal launcher
├── LICENSE                     # MIT License (scripts only)
├── REQUIREMENTS.md             # Third-party tool list with download links
├── README.md                   # This file
└── TOOLS/
    ├── Encryption/             # Encrypted Disk Detector (EDD)
    ├── FS_Acquisition/         # FTK Imager (GUI + CLI), Fuji
    ├── Live_Triage/            # osTriage
    ├── Other_Tools/            # CamStudio, Hasher, MouseJiggle,
    │                             NotMyFault, ProcessHacker, Terminal
    └── Vol_Acquisition/        # AVML, CyberTriage, KAPE,
                                  Magnet RESPONSE, UAC, WinPmem,
                                  Get-ClipHistory.ps1
```

## Windows Collection Workflow (win_IR.bat)

The Windows script provides an interactive, menu-driven collection process:

1. **Memory Acquisition** - Full physical memory dump via WinPmem
2. **Volatile Data Collection** - System info, network state, processes, services, scheduled tasks, user accounts, clipboard state and history, registry autoruns, VSS, disk info, BitLocker status, and encryption detection (EDD)
3. **CyberTriage** - Automated host-based triage collection
4. **KAPE** - Targeted artifact collection (KapeTriage + MemoryFiles); Modules not bundled — sync via `Get-KAPEUpdate.ps1` or `gkape.exe`
5. **Magnet RESPONSE** - Volatile data, system files, and ransomware note capture
6. **FTK Imager CLI** - Logical or physical disk imaging (E01 format)

Each step is optional and can be skipped or the script can be exited at any point.

## Clipboard History (win_clip_history.bat)

Windows clipboard history is stored **per user and per session** and is only reachable through the WinRT API from within that user's interactive session. `win_IR.bat` captures the clipboard feature state, the `cbdhsvc` service PID, and the pinned-item directories for every profile on disk, but the live history call it makes will usually return nothing when the script is run under an administrator account.

To capture the live history, run `win_clip_history.bat` **as the subject user, not elevated**:

```cmd
:: Run in the subject user's own session, WITHOUT elevation
win_clip_history.bat
```

The script confirms the executing account against the console user, warns if the console is elevated, and writes to `<drive>:\<HOSTNAME>\vol_data\clipboard_<username>\` — `clipboard_history.csv` (with SHA256), `_context.txt`, feature state, `cbdhsvc`/`rdpclip` process context, and pinned items.

Requires Windows 10 1809+ and Windows PowerShell 5.1 (PowerShell 7 cannot project the WinRT types). Keep the console window in the foreground during collection. If the history call fails, fall back to carving `cbdhsvc` from the memory image.

## Linux Collection Workflow (lin_IR.sh)

1. System information collection
2. Memory acquisition via AVML
3. Artifact collection via UAC (profile: ir_triage)

## macOS Collection Workflow (mac_IR.sh)

1. System information collection
2. Artifact collection via UAC (profile: ir_triage)
3. Filesystem acquisition via Fuji (GUI — launched manually)

## Usage

### Windows
```cmd
:: Run as Administrator from the IR_KIT directory
win_IR.bat

:: Then, in the subject user's own session and WITHOUT elevation
win_clip_history.bat
```

### Linux
```bash
# Run as root from the IR_KIT directory
chmod +x lin_IR.sh
sudo ./lin_IR.sh
```

### macOS
```bash
# Run as root from the IR_KIT directory
chmod +x mac_IR.sh
sudo ./mac_IR.sh
```

## Output

All collected data is saved to `<drive>:\<HOSTNAME>\` (Windows) or `<script_dir>/<hostname>/` (Linux/macOS), with a timestamped `log.txt` tracking each collection phase.

## Prerequisites

All third-party tools must be downloaded separately and placed in the appropriate `TOOLS/` subdirectories. See **REQUIREMENTS.md** for the complete list with download links and licensing information.

## Important Notes

- Always run with elevated privileges (Administrator / root) — the sole exception is `win_clip_history.bat`, which must run as the subject user
- Deploy from a dedicated USB drive when possible
- The scripts in this repository are licensed under MIT; the third-party tools in `TOOLS/` are subject to their own respective licenses
- Verify tool versions and update regularly
- Test in your environment before deploying to live incidents

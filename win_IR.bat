:: Windows Incident Response Script
:: By Jeremy Brice
:: dfir@cyberbyteir.com
:: Updated: 2026-11-12

@echo OFF

:: Check for administrator privileges - required for memory, disk, and registry operations
:: fltmc needs an elevated token and, unlike net session, does not depend on the Server service
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated
if /I "%~1"=="elevated" goto :elevatefailed
echo Administrator privileges required. Requesting elevation...
:: Paths are handed over in the environment so spaces, parentheses and ampersands survive
set "IRKIT_SELF=%~f0"
set "IRKIT_DIR=%~dp0"
powershell -NoProfile -Command "Start-Process -FilePath $env:ComSpec -ArgumentList ('/c \"\"' + $env:IRKIT_SELF + '\" elevated\"') -Verb RunAs -WorkingDirectory $env:IRKIT_DIR"
if not errorlevel 1 exit /b
echo Elevation was not obtained (declined, or PowerShell unavailable). Start this script from an elevated command prompt.
pause
exit /b 1

:elevatefailed
echo Elevation did not produce an administrator token. Run this script from an elevated command prompt.
pause
exit /b 1

:elevated
setlocal enabledelayedexpansion
set "default_mode=0"
set "issues=0"
set "bad_input=0"
set "how=operator selected"
set "kit_dir=%~dp0"
:: Loaded user hives: local/domain accounts (S-1-5-21) and Entra ID accounts (S-1-12-1)
set "sid_re=S-1-5-21-[0-9-]*$ S-1-12-1-[0-9-]*$"

:: Define output folder
:outputdrive
set "output_drive="
set /p output_drive=Drive letter for output [ex. D] (leave blank for %~d0\):
if not defined output_drive set "output_drive=%~d0"

:trim
if not defined output_drive goto :baddrive
set "LAST_CHAR=!output_drive:~-1!"
if "!LAST_CHAR!"=="\" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"=="/" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"==":" set "output_drive=!output_drive:~0,-1!" & goto trim

:: Must be a single letter of a drive that exists
if not "!output_drive:~1!"=="" goto :baddrive
set "drive_ok="
for %%L in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /I "!output_drive!"=="%%L" set "drive_ok=1"
if not defined drive_ok goto :baddrive
if not exist "!output_drive!:\" goto :baddrive

set "output_dir=%output_drive%:\%COMPUTERNAME%"
set "vol=%output_dir%\vol_data"
set "log_file=%output_dir%\log.txt"

if not exist "%output_dir%\" mkdir "%output_dir%"
>> "%log_file%" echo ==== IR Kit win_IR.bat ====
if not exist "%log_file%" (
    echo [33m Cannot write to %output_dir% - choose another drive [0m
    goto :outputdrive
)
goto :loghead

:baddrive
echo [33m Invalid or unavailable drive - enter a single drive letter [0m
set /a bad_input+=1
if !bad_input! lss 20 goto :outputdrive
echo No valid input after 20 attempts - exiting
pause
exit /b 1

:: Record host, account, system clock and time zone before anything is collected
:loghead
echo Hostname: %COMPUTERNAME%
>> "%log_file%" echo Hostname                  : %COMPUTERNAME%
>> "%log_file%" echo Script                    : "%~f0"
>> "%log_file%" echo System clock (cmd, local) : %date% %time%
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "$n=Get-Date; $tz=[TimeZoneInfo]::Local; $os=Get-CimInstance Win32_OperatingSystem; $cs=Get-CimInstance Win32_ComputerSystem; $me=[Security.Principal.WindowsIdentity]::GetCurrent().Name; 'Collection started (UTC)  : '+$n.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); 'System clock (local)      : '+$n.ToString('yyyy-MM-ddTHH:mm:sszzz'); 'Time zone                 : '+$tz.Id+' / '+$tz.DisplayName; 'UTC offset (current)      : '+$tz.GetUtcOffset($n); 'Daylight saving in effect : '+$tz.IsDaylightSavingTime($n); 'Last boot (UTC)           : '+$os.LastBootUpTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); 'Running as                : '+$me; 'Console user              : '+$(if($cs.UserName){$cs.UserName}else{'none detected'}); if($cs.UserName -and ($cs.UserName -ne $me)){'WARNING: Running account differs from the console user. Per-user items (environment variables, net use, clipboard history) reflect the running account.'}" 2^>^&1`) do (
    echo %%L
    >> "%log_file%" echo %%L
)
>> "%log_file%" echo NOTE: Compare the system clock above with a trusted time source and record any offset.
>> "%log_file%" echo Log entries below are stamped in UTC unless marked local (PowerShell unavailable).

:memorychoice
set "c="
set /P c=[32m Acquire Memory? [Y/N][D for Default (Memory, Volatile, CyberTriage, Kape)] [E to End]? [0m
if /I "!c!"=="Y" (set "how=operator selected" & goto :memory)
if /I "!c!"=="N" (call :log "Operator declined Memory acquisition" & goto :voldatachoice)
if /I "!c!"=="D" (set "default_mode=1" & set "how=Default mode" & goto :memory)
if /I "!c!"=="E" (call :log "Operator ended the run at the Memory acquisition prompt" & goto :done)
call :invalid "Invalid selection" || goto :noinput
goto :memorychoice

:memory
if not exist "%kit_dir%TOOLS\Vol_Acquisition\winpmem\winpmem_mini_x64_rc2.exe" (
    call :log "SKIPPED: Memory acquisition - tool missing: TOOLS\Vol_Acquisition\winpmem\winpmem_mini_x64_rc2.exe"
    goto :voldatachoice
)
call :log "Started Memory acquisition - !how!"

 :: Aquire Memory - tools are started by full path: a bare name fails where NoDefaultCurrentDirectoryInExePath is set
 cd /D "%kit_dir%TOOLS\Vol_Acquisition\winpmem"
"%kit_dir%TOOLS\Vol_Acquisition\winpmem\winpmem_mini_x64_rc2.exe" "%output_dir%\physmem.raw"
set "rc=!errorlevel!"

:: Success is judged on the image itself, not on the exit code alone
set "mem_size=0"
for %%F in ("%output_dir%\physmem.raw") do if exist "%%~fF" set "mem_size=%%~zF"
if "!mem_size!"=="0" (
    call :log "FAILED: Memory acquisition - exit code !rc!, no image written to %output_dir%\physmem.raw"
    goto :voldatachoice
)
if not "!rc!"=="0" (
    call :log "WARNING: Memory acquisition ended with exit code !rc! - physmem.raw is !mem_size! bytes, verify the image"
    goto :voldatachoice
)
call :log "Completed Memory acquisition - physmem.raw !mem_size! bytes"

:voldatachoice
if "%default_mode%"=="1" goto :voldata
set "c="
set /P c=[32m Acquire Volatile Data? [Y/N][E to End]? [0m
if /I "!c!"=="Y" (set "how=operator selected" & goto :voldata)
if /I "!c!"=="N" (call :log "Operator declined Volatile Data acquisition" & goto :cybertriagechoice)
if /I "!c!"=="E" (call :log "Operator ended the run at the Volatile Data acquisition prompt" & goto :done)
call :invalid "Invalid selection" || goto :noinput
goto :voldatachoice

:voldata
cd /D "%kit_dir%"
if not exist "%vol%\" mkdir "%vol%"

call :log "Started Volatile Data acquisition - !how!"

 :: DNS cache first - most volatile, and nothing below may add to it before it is saved
 echo Collecting DNS cache
 ipconfig /displaydns >> "%vol%\network_dns_cache.txt" 2>&1 || call :warn "ipconfig /displaydns" "network_dns_cache.txt"

 :: Acquire system information
 :: doskey /history is not collected: it only returns the history of this script's own console
 echo Collecting system information
 systeminfo >> "%vol%\systeminfo.txt" 2>&1 || call :warn "systeminfo" "systeminfo.txt"
 set >> "%vol%\environmental_variables.txt" 2>&1
 w32tm /tz >> "%vol%\system_time.txt" 2>&1 || call :warn "w32tm /tz" "system_time.txt"
 :: w32tm /query only answers while the Windows Time service runs, and a stopped service is
 :: common on machines that are not domain-joined. That is a finding, not a collection
 :: failure, so the service state and its configuration are recorded alongside the query
 sc query w32time >> "%vol%\system_time.txt" 2>&1
 w32tm /query /status >> "%vol%\system_time.txt" 2>&1
 reg query "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" >> "%vol%\system_time.txt" 2>&1

 echo Collecting PowerShell history (all users)
 for /D %%U in ("%SystemDrive%\Users\*") do (
     if exist "%%~fU\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\" (
         robocopy "%%~fU\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine" "%vol%\PS_history\%%~nxU" *.txt /COPY:DAT /R:0 /W:0 /NFL /NDL /NJH /NJS >nul 2>&1
         if errorlevel 8 call :warn "robocopy PSReadLine history for %%~nxU" "PS_history\%%~nxU"
     )
 )

 echo Collecting network information
 ipconfig /all >> "%vol%\network_ipconfig_all.txt" 2>&1 || call :warn "ipconfig /all" "network_ipconfig_all.txt"
 netstat -anob >> "%vol%\network_netstat_anob.txt" 2>&1 || call :warn "netstat -anob" "network_netstat_anob.txt"
 powershell -Command "get-nettcpconnection" >> "%vol%\network_connections.txt" 2>&1 || call :warn "Get-NetTCPConnection" "network_connections.txt"
 netsh advfirewall show all >> "%vol%\network_firewall.txt" 2>&1 || call :warn "netsh advfirewall show all" "network_firewall.txt"
 netsh wlan show all >> "%vol%\network_wifi.txt" 2>&1 || call :warn "netsh wlan show all" "network_wifi.txt"
 arp -a >> "%vol%\network_gateways.txt" 2>&1 || call :warn "arp -a" "network_gateways.txt"
 net share >> "%vol%\network_shares.txt" 2>&1 || call :warn "net share" "network_shares.txt"
 net session >> "%vol%\network_net_session.txt" 2>&1 || call :warn "net session" "network_net_session.txt"
 :: net use only shows mappings of this elevated logon session; the per-user Network keys
 :: below hold the persistent mapped drives of every logged-on user
 net use >> "%vol%\network_net_use.txt" 2>&1 || call :warn "net use" "network_net_use.txt"
 for /f "delims=" %%S in ('reg query HKU ^| findstr /R "%sid_re%"') do (
     echo ==== %%S\Network ====
     reg query "%%S\Network" /s
 ) >> "%vol%\network_net_use.txt" 2>&1
 qwinsta >> "%vol%\network_RDP_sessions.txt" 2>&1 || call :warn "qwinsta" "network_RDP_sessions.txt"
 :: Outbound lookup - kept last so it cannot alter the network state collected above
 powershell -Command "Invoke-RestMethod -Uri 'https://ipinfo.io/ip' -TimeoutSec 10" >> "%vol%\network_external_IP.txt" 2>&1 || call :warn "external IP lookup (ipinfo.io)" "network_external_IP.txt"
 :: Optionally enable to resolve FQDN on target system
 ::netstat -f >> "%vol%\network_netstat_f.txt"

 echo Collecting processes
 tasklist /v >> "%vol%\tasklist.txt" 2>&1 || call :warn "tasklist /v" "tasklist.txt"

 echo Collecting services
 sc queryex type= all state= all >> "%vol%\services.txt" 2>&1 || call :warn "sc queryex type= all state= all" "services.txt"
 reg query HKLM\System\CurrentControlSet\Services /s >> "%vol%\services_reg.txt" 2>&1 || call :warn "reg query Services" "services_reg.txt"

 echo Collecting scheduled tasks
 schtasks /query >> "%vol%\schTasks.txt" 2>&1 || call :warn "schtasks /query" "schTasks.txt"
 schtasks /query /fo LIST /v >> "%vol%\schTasks_v.txt" 2>&1 || call :warn "schtasks /query /fo LIST /v" "schTasks_v.txt"

 :: A key that does not exist is normal here; the reg error is kept in the output file
 echo Collecting ASEPs
 for %%K in (
     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
     "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"
     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
     "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
     "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
     "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
     "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components"
 ) do (
     echo ==== %%~K ====
     reg query %%K /s
 ) >> "%vol%\ASEPs.txt" 2>&1
 echo ==== HKLM\SYSTEM\CurrentControlSet\Control\Session Manager ==== >> "%vol%\ASEPs.txt"
 reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" >> "%vol%\ASEPs.txt" 2>&1
 for /f "delims=" %%S in ('reg query HKU ^| findstr /R "%sid_re%"') do (
     for %%R in (Run RunOnce) do (
         echo ==== %%S\Software\Microsoft\Windows\CurrentVersion\%%R ====
         reg query "%%S\Software\Microsoft\Windows\CurrentVersion\%%R"
     )
 ) >> "%vol%\ASEPs.txt" 2>&1
 dir /a /t:c "%ProgramData%\Microsoft\Windows\Start Menu\Programs\StartUp" >> "%vol%\ASEPs_startup_folders.txt" 2>&1
 for /D %%U in ("%SystemDrive%\Users\*") do dir /a /t:c "%%~fU\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" >> "%vol%\ASEPs_startup_folders.txt" 2>&1
 reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" /s /v Debugger >> "%vol%\ASEPs_ifeo.txt" 2>&1
 reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" /s /v Debugger >> "%vol%\ASEPs_ifeo.txt" 2>&1
 reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit" /s >> "%vol%\ASEPs_ifeo.txt" 2>&1

 :: query user exits 1 even when it lists sessions, so its exit code is not checked
 echo Collecting user information
 query user >> "%vol%\users_loggedon.txt" 2>&1
 net user >> "%vol%\users.txt" 2>&1 || call :warn "net user" "users.txt"
 net localgroup administrators >> "%vol%\users_admins.txt" 2>&1 || call :warn "net localgroup administrators" "users_admins.txt"
 powershell -Command "Get-WmiObject Win32_UserAccount -filter LocalAccount=True" >> "%vol%\users_all.txt" 2>&1 || call :warn "Get-WmiObject Win32_UserAccount" "users_all.txt"
 reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" /s /v ProfileImagePath >> "%vol%\users_profiles.txt" 2>&1 || call :warn "reg query ProfileList" "users_profiles.txt"

 :: Clipboard settings are read for every logged-on user, not only the elevated account
 echo Collecting clipboard history
 for /f "delims=" %%S in ('reg query HKU ^| findstr /R "%sid_re%"') do (
     echo ==== %%S\Software\Microsoft\Clipboard ====
     reg query "%%S\Software\Microsoft\Clipboard"
 ) >> "%vol%\clipboard_settings.txt" 2>&1
 tasklist /svc /fi "imagename eq svchost.exe" | findstr /i cbdhsvc >> "%vol%\clipboard_cbdhsvc_pid.txt" 2>&1
 for /D %%U in ("%SystemDrive%\Users\*") do (
     if exist "%%~fU\AppData\Local\Microsoft\Windows\Clipboard" (
         robocopy "%%~fU\AppData\Local\Microsoft\Windows\Clipboard" "%vol%\clipboard_pinned\%%~nxU" /E /COPY:DAT /R:0 /W:0 /NFL /NDL /NJH /NJS >nul 2>&1
         if errorlevel 8 call :warn "robocopy pinned clipboard for %%~nxU" "clipboard_pinned\%%~nxU"
     )
 )
 if not exist "%kit_dir%TOOLS\Vol_Acquisition\Get-ClipHistory.ps1" (
     call :log "SKIPPED: Clipboard history retrieval - script missing: TOOLS\Vol_Acquisition\Get-ClipHistory.ps1"
     goto :vss
 )
 powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%kit_dir%TOOLS\Vol_Acquisition\Get-ClipHistory.ps1" -OutputDir "%vol%" >> "%vol%\clipboard_collection_log.txt" 2>&1
 set "rc=!errorlevel!"
 if not "!rc!"=="0" (
     call :log "FAILED: Clipboard history retrieval - exit code !rc!, see vol_data\clipboard_collection_log.txt. For another account's history run win_clip_history.bat in that user's session"
 ) else (
     call :log "Clipboard history retrieved"
 )

:vss
 echo Collecting volume shadow copies
 vssadmin list shadows >> "%vol%\VSS.txt" 2>&1 || call :warn "vssadmin list shadows" "VSS.txt"

 echo Collecting disk information (disks 0-10)
(
    for /L %%N in (0,1,10) do (
        echo select disk %%N
        echo list partition
        echo detail disk
    )
) > "%vol%\diskpart_commands.txt"
diskpart /s "%vol%\diskpart_commands.txt" >> "%vol%\diskpart.txt" 2>&1 || call :warn "diskpart" "diskpart.txt"

echo Collecting BitLocker / encryption information...
manage-bde.exe -status >> "%vol%\bde-status.txt" 2>&1 || call :warn "manage-bde -status" "bde-status.txt"
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    echo Drive %%D: >> "%vol%\bde-protectors.txt"
    manage-bde.exe -protectors %%D: -get >> "%vol%\bde-protectors.txt" 2>&1
)


:: Run Encrypted Disk Detector
if not exist "%kit_dir%TOOLS\Encryption\EDDv310.exe" (
    call :log "SKIPPED: Encrypted Disk Detector - tool missing: TOOLS\Encryption\EDDv310.exe"
    goto :voldatadone
)
cd /D "%kit_dir%TOOLS\Encryption"
:: EDD v3.1.0 exits non-zero on a completed run that reports encryption, so the result is
:: read from the lines this run adds to EDD.txt rather than from the exit code alone
set "edd_before=0"
set "edd_after=0"
for /f %%C in ('findstr /C:"were detected by EDD" "%vol%\EDD.txt" 2^>nul ^| find /c /v ""') do set "edd_before=%%C"
"%kit_dir%TOOLS\Encryption\EDDv310.exe" /batch >> "%vol%\EDD.txt" 2>&1
set "rc=!errorlevel!"
for /f %%C in ('findstr /C:"were detected by EDD" "%vol%\EDD.txt" 2^>nul ^| find /c /v ""') do set "edd_after=%%C"
if !edd_after! gtr !edd_before! (
    call :log "NOTICE: Encrypted Disk Detector reports encrypted volumes or processes - exit code !rc!, see vol_data\EDD.txt"
    goto :voldatadone
)
if not "!rc!"=="0" (
    call :log "WARNING: EDDv310.exe /batch returned exit code !rc! and reported no detection - review vol_data\EDD.txt"
    goto :voldatadone
)
call :log "Encrypted Disk Detector completed - no encryption reported"

:voldatadone
call :log "Completed Volatile Data acquisition"

:: Primary scan and acquisition of data Files
:cybertriagechoice
if "%default_mode%"=="1" goto :cybertriage
set "c="
set /P c=[32m Run CyberTriage? [Y/N][E to End]? [0m
if /I "!c!"=="Y" (set "how=operator selected" & goto :cybertriage)
if /I "!c!"=="N" (call :log "Operator declined CyberTriage acquisition" & goto :kapechoice)
if /I "!c!"=="E" (call :log "Operator ended the run at the CyberTriage acquisition prompt" & goto :done)
call :invalid "Invalid selection" || goto :noinput
goto :cybertriagechoice

:cybertriage
if not exist "%kit_dir%TOOLS\Vol_Acquisition\cybertriage\CyberTriageCollector.exe" (
    call :log "SKIPPED: CyberTriage acquisition - tool missing: TOOLS\Vol_Acquisition\cybertriage\CyberTriageCollector.exe"
    goto :kapechoice
)
if not exist "%output_dir%\cybertriage\" mkdir "%output_dir%\cybertriage"
cd /D "%kit_dir%TOOLS\Vol_Acquisition\cybertriage"
call :log "Started CyberTriage acquisition - !how!"
start "" /wait "%kit_dir%TOOLS\Vol_Acquisition\cybertriage\CyberTriageCollector.exe" -o "%output_dir%\cybertriage\cybertriage" --tempdir "%output_dir%\cybertriage"
call :finish "CyberTriage acquisition" "%output_dir%\cybertriage"

:: Primary acquisition of System Files and Logs
:kapechoice
if "%default_mode%"=="1" goto :kape
set "c="
set /P c=[32m Run KAPE Collection? [Y/N][E to End]? [0m
if /I "!c!"=="Y" (set "how=operator selected" & goto :kape)
if /I "!c!"=="N" (call :log "Operator declined Kape acquisition" & goto :ftkchoice)
if /I "!c!"=="E" (call :log "Operator ended the run at the Kape acquisition prompt" & goto :done)
call :invalid "Invalid selection" || goto :noinput
goto :kapechoice

:kape
if not exist "%kit_dir%TOOLS\Vol_Acquisition\KAPE\kape.exe" (
    call :log "SKIPPED: Kape acquisition - tool missing: TOOLS\Vol_Acquisition\KAPE\kape.exe"
    goto :ftkchoice
)
cd /D "%kit_dir%TOOLS\Vol_Acquisition\KAPE"
call :log "Started Kape acquisition - !how!"
start "" /wait "%kit_dir%TOOLS\Vol_Acquisition\KAPE\kape.exe" --tsource C: --tdest "%output_dir%\kape" --target KapeTriage,MemoryFiles --vhd collection --zv false
call :finish "Kape acquisition" "%output_dir%\kape"

:: Acquire Logical Image of Drive
:ftkchoice
set "c="
set /P c=[32m Run FTK File System Acquisition? [Y/N][E to End]? [0m
if /I "!c!"=="Y" (set "how=operator selected" & goto :ftk)
if /I "!c!"=="N" (call :log "Operator declined FTK File System acquisition" & goto :done)
if /I "!c!"=="E" (call :log "Operator ended the run at the FTK File System acquisition prompt" & goto :done)
call :invalid "Invalid selection" || goto :noinput
goto :ftkchoice

:ftk
if not exist "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline\ftkimager.exe" (
    call :log "SKIPPED: FTK acquisition - tool missing: TOOLS\FS_Acquisition\FTK_Imager-commandline\ftkimager.exe"
    goto :done
)
cd /D "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline"
echo Running FTK
echo C:\ encryption status
manage-bde -status C: | findstr "Protection"
"%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline\ftkimager.exe" --list-drives

:ftkdrive
set "c="
set /P c=[33m Enter drive to image (Logical Drive Letter [C,D,E,etc.], PhysicalDrive# [0,1,2,etc.], or 'done' to cancel):  [0m
if /I "!c!"=="done" (call :log "Operator finished FTK drive selection" & goto :done)
set "ftk_kind="
for %%L in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /I "!c!"=="%%L" set "ftk_kind=logical"
for /L %%N in (0,1,99) do if "!c!"=="%%N" set "ftk_kind=physical"
if "!ftk_kind!"=="logical" goto :ftkLogical
if "!ftk_kind!"=="physical" goto :ftkPhysical
call :invalid "Invalid entry - enter a single drive letter, a disk number, or 'done'" || goto :noinput
goto :ftkdrive

:ftkLogical
if not exist "%output_dir%\ftk\" mkdir "%output_dir%\ftk"
cd /D "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline"
call :log "Started FTK Logical acquisition of !c!: - !how!"
start "" /wait "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline\ftkimager.exe" !c!:"%output_dir%\ftk\log_image_!c!" --e01 --compress 6 --no-sha1
call :finish "FTK Logical acquisition of !c!:" "%output_dir%\ftk\log_image_!c!.E01"
goto :ftkdrive

:ftkPhysical
if not exist "%output_dir%\ftk\" mkdir "%output_dir%\ftk"
cd /D "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline"
call :log "Started FTK Physical acquisition of PhysicalDrive!c! - !how!"
start "" /wait "%kit_dir%TOOLS\FS_Acquisition\FTK_Imager-commandline\ftkimager.exe" \\.\PHYSICALDRIVE!c! "%output_dir%\ftk\phys_image_!c!" --e01 --compress 6 --no-sha1
call :finish "FTK Physical acquisition of PhysicalDrive!c!" "%output_dir%\ftk\phys_image_!c!.E01"
goto :ftkdrive

:: Reached when the prompts stop receiving usable answers, e.g. input is redirected and exhausted
:noinput
call :log "FAILED: No valid input after 20 attempts - ending acquisition"

:done
call :log "Completed Acquisition - !issues! FAILED/WARNING/SKIPPED entries"
echo [32m Log: %log_file% [0m
pause
exit /b 0

:: ---------------------------------------------------------------------------
:: Subroutines
:: ---------------------------------------------------------------------------

:: call :log "message" - UTC ISO-8601 stamped entry to the console and log.txt
:log
set "msg=%~1"
set "ts="
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')" 2^>nul`) do set "ts=%%T"
if not defined ts set "ts=%date% %time% local"
set "flag="
if "!msg:~0,6!"=="FAILED" set "flag=1"
if "!msg:~0,7!"=="WARNING" set "flag=1"
if "!msg:~0,7!"=="SKIPPED" set "flag=1"
if defined flag set /a issues+=1
:: NOTICE entries are highlighted but are findings, not collection problems, so they are not counted
if "!msg:~0,6!"=="NOTICE" set "flag=1"
if defined flag (
    echo [33m !ts!: !msg! [0m
) else (
    echo !ts!: !msg!
)
>> "%log_file%" echo !ts!: !msg!
exit /b 0

:: call :invalid "message" || goto :noinput - rejects an answer; errorlevel 1 after 20 rejections in a run
:invalid
set /a bad_input+=1
echo %~1
if !bad_input! geq 20 exit /b 1
exit /b 0

:: command || call :warn "command" "file under vol_data" - logs the exit code of a failed collector
:warn
set "rc=!errorlevel!"
call :log "WARNING: %~1 returned exit code !rc! - review vol_data\%~2"
exit /b 0

:: call :finish "phase" "expected output" - straight after a tool, classifies the result
:finish
set "rc=!errorlevel!"
dir /b /a "%~2" 2>nul | findstr "^" >nul
if errorlevel 1 (
    call :log "FAILED: %~1 - exit code !rc!, no output found at %~2"
    exit /b 0
)
if not "!rc!"=="0" (
    call :log "WARNING: %~1 ended with exit code !rc! - output present, verify it"
    exit /b 0
)
call :log "Completed %~1"
exit /b 0

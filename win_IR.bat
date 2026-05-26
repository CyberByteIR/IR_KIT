:: Windows Incident Response Script
:: By Jeremy Brice
:: forensics@cyberbyteconsulting.com
:: Updated: 2026-05-26

@echo OFF

:: Check for administrator privileges - required for memory, disk, and registry operations
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator privileges required. Requesting elevation...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

setlocal enabledelayedexpansion
set "default_mode=0"

:: Define output folder
set /p output_drive=Drive letter for output [ex. D] (leave blank for %~d0\):
if "%output_drive%"=="" set "output_drive=%~d0"

:trim
set "LAST_CHAR=!output_drive:~-1!"
if "!LAST_CHAR!"=="\" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"=="/" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"==":" set "output_drive=!output_drive:~0,-1!" & goto trim

set output_dir=%output_drive%:\%COMPUTERNAME%

mkdir %output_dir%

echo Hostname: %COMPUTERNAME%
echo Hostname: %COMPUTERNAME% >> "%output_dir%\log.txt"

:memorychoice
set /P c=[32m Acquire Memory? [Y/N][D for Default] [E to End]? [0m
if /I "%c%" EQU "Y" goto :memory
if /I "%c%" EQU "N" goto :voldatachoice
if /I "%c%" EQU "D" (set "default_mode=1" & goto :memory)
if /I "%c%" EQU "E" goto :done

:memory
echo %date%-%time%: Started Memory acquisition
echo %date%-%time%: Started Memory acquisition >> "%output_dir%\log.txt"

 :: Aquire Memory
 cd /D %~dp0TOOLS\Vol_Acquisition\winpmem
winpmem_mini_x64_rc2.exe %output_dir%\physmem.raw

echo %date%-%time%: Completed Memory acquisition
echo %date%-%time%: Completed Memory acquisition >> "%output_dir%\log.txt"

:voldatachoice
if "%default_mode%"=="1" (set "c=Y") else (
    set "c="
set /P c=[32m Acquire Volatile Data? [Y/N][E to End]? [0m
)
if /I "%c%" EQU "Y" goto :voldata
if /I "%c%" EQU "N" goto :cybertriagechoice
if /I "%c%" EQU "E" goto :done

:voldata
cd /D %~dp0
mkdir %output_dir%\vol_data

echo %date%-%time%: Started Volatile Data acquisition
echo %date%-%time%: Started Volatile Data acquisition >> "%output_dir%\log.txt"

 :: Acquire system information
 echo Collecting system information
 doskey /history >> "%output_dir%\vol_data\CLI_history.txt"
 powershell -Command "Get-Content (Get-PSReadlineOption).HistorySavePath" >> "%output_dir%\vol_data\PS_history.txt"
 systeminfo >> "%output_dir%\vol_data\systeminfo.txt"
 set >> "%output_dir%\vol_data\environmental_variables.txt"
 
 echo Collecting network information
 ipconfig /all >> "%output_dir%\vol_data\network_ipconfig_all.txt"
 netstat -anob >> "%output_dir%\vol_data\network_netstat_anob.txt"
 powershell -Command "get-nettcpconnection" >> "%output_dir%\vol_data\network_connections.txt"
 netsh advfirewall show all >> "%output_dir%\vol_data\network_firewall.txt"
 netsh wlan show all >> "%output_dir%\vol_data\network_wifi.txt"
 arp -a >> "%output_dir%\vol_data\network_gateways.txt"
 net share >> "%output_dir%\vol_data\network_shares.txt"
 qwinsta >> "%output_dir%\vol_data\network_RDP_sessions.txt"
 powershell -Command "Invoke-RestMethod -Uri 'https://ipinfo.io/ip'" >> "%output_dir%\vol_data\network_external_IP.txt"
 :: Optionally enable to resolve FQDN on target system
 ::netstat -f >> "%output_dir%\vol_data\network_netstat_f.txt"

 echo Collecting processes
 tasklist /v >> "%output_dir%\vol_data\tasklist.txt"

 echo Collecting services
 sc queryex >> "%output_dir%\vol_data\services.txt"

 echo Collecting scheduled tasks
 schtasks /query >> "%output_dir%\vol_data\schTasks.txt"
 schtasks /query /fo LIST /v >> "%output_dir%\vol_data\schTasks_v.txt"

 echo Collecting user information
 query user >> "%output_dir%\vol_data\users_loggedon.txt"
 net user >> "%output_dir%\vol_data\users.txt"
 net localgroup administrators >> "%output_dir%\vol_data\users_admins.txt"
 powershell -Command "Get-WmiObject Win32_UserAccount -filter LocalAccount=True" >> "%output_dir%\vol_data\users_all.txt"

 echo Collecting registry information
 reg query HKLM\Software\Microsoft\Windows\CurrentVersion\Run >> "%output_dir%\vol_data\reg_autoruns.txt"
 reg query HKLM\System\CurrentControlSet\Services >> "%output_dir%\vol_data\reg_services.txt"

 echo Collecting volume shadow copies
 vssadmin list shadows >> "%output_dir%\vol_data\VSS.txt"

 echo Collecting disk information (disks 0-10)
(
    for /L %%N in (0,1,10) do (
        echo select disk %%N
        echo list partition
        echo detail disk
    )
) > "%output_dir%\vol_data\diskpart_commands.txt"
diskpart /s "%output_dir%\vol_data\diskpart_commands.txt" >> "%output_dir%\vol_data\diskpart.txt"

echo Collecting BitLocker / encryption information...
manage-bde.exe -status >> "%output_dir%\vol_data\bde-status.txt"
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    echo Drive %%D: >> "%output_dir%\vol_data\bde-protectors.txt"
    manage-bde.exe -protectors %%D: -get >> "%output_dir%\vol_data\bde-protectors.txt" 2>&1
)


:: Run Encrypted Disk Detector
cd /D %~dp0TOOLS\Encryption
EDDv310.exe /batch >> "%output_dir%\vol_data\EDD.txt"

echo %date%-%time%: Completed Volatile Data acquisition
echo %date%-%time%: Completed Volatile Data acquisition >> "%output_dir%\log.txt"

:: Primary scan and acquisition of data Files
:cybertriagechoice
if "%default_mode%"=="1" (set "c=Y") else (
    set "c="
set /P c=[32m Run CyberTriage? [Y/N][E to End]? [0m
)
if /I "%c%" EQU "Y" goto :cybertriage
if /I "%c%" EQU "N" goto :kapechoice
if /I "%c%" EQU "E" goto :done

:cybertriage
mkdir "%output_dir%\cybertriage"
cd /D %~dp0TOOLS\Vol_Acquisition\cybertriage
echo %date%-%time%: Started CyberTriage acquisition 
echo %date%-%time%: Started CyberTriage acquisition >> "%output_dir%\log.txt"
start /wait CyberTriageCollector.exe -o "%output_dir%\cybertriage\cybertriage" --tempdir "%output_dir%\cybertriage" 
echo %date%-%time%: Completed CyberTriage acquisition 
echo %date%-%time%: Completed CyberTriage acquisition >> "%output_dir%\log.txt"

:: Primary acquisition of System Files and Logs
:kapechoice
if "%default_mode%"=="1" (set "c=Y") else (
    set "c="
set /P c=[32m Run KAPE Collection? [Y/N][E to End]? [0m
)
if /I "%c%" EQU "Y" goto :kape
if /I "%c%" EQU "N" goto :magnetchoice
if /I "%c%" EQU "E" goto :done

:kape
cd /D %~dp0TOOLS\Vol_Acquisition\KAPE
echo %date%-%time%: Started Kape acquisition 
echo %date%-%time%: Started Kape acquisition >> "%output_dir%\log.txt"
start /wait kape.exe --tsource C: --tdest "%output_dir%\kape" --target KapeTriage,MemoryFiles --vhd collection --zv false
echo %date%-%time%: Completed Kape acquisition 
echo %date%-%time%: Completed Kape acquisition >> "%output_dir%\log.txt"

:: Secondary acquisition of volatile data
:magnetchoice
if "%default_mode%"=="1" (set "c=N") else (
    set "c="set /P c=[32m Run Magnet Collection? [Y/N][E to End]? [0m
	)
if /I "%c%" EQU "Y" goto :magnet
if /I "%c%" EQU "N" goto :ftkchoice
if /I "%c%" EQU "E" goto :done

:magnet
cd /D %~dp0TOOLS\Vol_Acquisition\Magnet
echo %date%-%time%: Started Magnet Response acquisition (please be patient as this is run silently)
echo %date%-%time%: Started Magnet Response acquisition >> "%output_dir%\log.txt"
start /wait MagnetRESPONSE.exe /accepteula /nodiagnosticdata /unattended /silent /output:"%output_dir%\magnet" /caseref:"" /capturevolatile /capturesystemfiles /captureransomnotes
echo %date%-%time%: Completed Magnet Response acquisition 
echo %date%-%time%: Completed Magnet Response acquisition >> "%output_dir%\log.txt"

:: Acquire Logical Image of Drive
:ftkchoice
set /P c=[32m Run FTK File System Acquisition? [Y/N][E to End]? [0m
if /I "%c%" EQU "Y" goto :ftk
if /I "%c%" EQU "N" goto :done
if /I "%c%" EQU "E" goto :done

:ftk
cd /D %~dp0TOOLS\FS_Acquisition\FTK_Imager-commandline
echo Running FTK
echo C:\ encryption status
manage-bde -status C: | findstr "Protection"
ftkimager.exe --list-drives

:ftkdrive
set /P c=[33m Enter drive to image (Logical Drive Letter [C,D,E,etc.], PhysicalDrive# [0,1,2,etc.], or 'done' to cancel):  [0m
if /I "%c%" EQU "done" goto :done
echo "%c%" | findstr /R "^[A-Z]$" >nul && goto :ftkLogical
for /L %%N in (0,1,9) do if "%c%"=="%%N" goto :ftkPhysical

:ftkLogical
mkdir %output_dir%\ftk
cd /D %~dp0TOOLS\FS_Acquisition\FTK_Imager-commandline
echo %date%-%time%: Started FTK Logical acquisition 
echo %date%-%time%: Started FTK Logical acquisition >> "%output_dir%\log.txt"
start /wait ftkimager.exe %c%: "%output_dir%\ftk\log_image_%c%" --e01 --compress 6 --no-sha1
echo %date%-%time%: Completed FTK Logical acquisition 
echo %date%-%time%: Completed FTK Logical acquisition >> "%output_dir%\log.txt"
goto :ftkdrive

:ftkPhysical
mkdir %output_dir%\ftk
cd /D %~dp0TOOLS\FS_Acquisition\FTK_Imager-commandline
echo %date%-%time%: Started FTK Physical acquisition 
echo %date%-%time%: Started FTK Physical acquisition >> "%output_dir%\log.txt"
start /wait ftkimager.exe \\.\PHYSICALDRIVE%c% "%output_dir%\ftk\phys_image_%c%" --e01 --compress 6 --no-sha1
echo %date%-%time%: Completed FTK Physical acquisition 
echo %date%-%time%: Completed FTK Physical acquisition >> "%output_dir%\log.txt"
goto :ftkdrive

:done
echo [32m %date%-%time%: Completed Acquisition  [0m
echo %date%-%time%: Completed Acquisition >> "%output_dir%\log.txt"
pause
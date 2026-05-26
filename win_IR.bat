:: Windows Incident Response Script
:: By Jeremy Brice
:: forensics@cyberbyteconsulting.com
:: Updated: 2026-05-26

@echo OFF

:: Check for administrator privileges � required for memory, disk, and registry operations
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator privileges required. Requesting elevation...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

setlocal enabledelayedexpansion

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
set /P c=[32m Acquire Memory? [Y/N/][E to End]? [0m
if /I "%c%" EQU "Y" goto :memory
if /I "%c%" EQU "N" goto :voldatachoice
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
set /P c=[32m Acquire Volatile Data? [Y/N/][E to End]? [0m
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
 powershell -Command "Invoke-RestMethod" -Uri "https://api.ipify.org" >> "%output_dir%\vol_data\network_external_IP.txt"
 netstat -f >> "%output_dir%\vol_data\network_netstat_f.txt"

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

 echo Collecting disk information
 echo list disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 0 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 1 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 2 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 3 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 4 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 5 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 6 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 7 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 8 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 9 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo select disk 10 >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo list partition >> "%output_dir%\vol_data\diskpart_commands.txt"
 echo detail disk >> "%output_dir%\vol_data\diskpart_commands.txt"
 diskpart /s "%output_dir%\vol_data\diskpart_commands.txt" >> "%output_dir%\vol_data\diskpart.txt"
 del "%output_dir%\vol_data\diskpart_commands.txt"

 echo Collecting Bitlocker and encryption information
 manage-bde.exe -status >> "%output_dir%\vol_data\bde-status.txt" 
 echo Drive C: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors C: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive A: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors A: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive B: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors B: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive D: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors D: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive E: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors E: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive F: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors F: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive G: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors G: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive H: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors H: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive I: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors I: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive J: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors J: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive K: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors K: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive L: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors L: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive M: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors M: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive N: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors N: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive O: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors O: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive P: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors P: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive Q: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors Q: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive R: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors R: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive S: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors S: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive T: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors T: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive U: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors U: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive V: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors V: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive W: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors W: -get >> "%output_dir%\vol_data\bde-protectors.txt" 
 echo Drive X: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors X: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive Y: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors Y: -get >> "%output_dir%\vol_data\bde-protectors.txt"
 echo Drive Z: >> "%output_dir%\vol_data\bde-protectors.txt"
 manage-bde.exe -protectors Z: -get >> "%output_dir%\vol_data\bde-protectors.txt" 


:: Run Encrypted Disk Detector
cd /D %~dp0TOOLS\Encryption
EDDv310.exe /batch >> "%output_dir%\vol_data\EDD.txt"

echo %date%-%time%: Completed Volatile Data acquisition
echo %date%-%time%: Completed Volatile Data acquisition >> "%output_dir%\log.txt"

:: Primary scan and acquisition of data Files
:cybertriagechoice
set /P c=[32m Run CyberTriage? [Y/N/][E to End]? [0m
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
set /P c=[32m Run KAPE Collection? [Y/N][E to End]? [0m
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
set /P c=[32m Run Magnet Collection? [Y/N][E to End]? [0m
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

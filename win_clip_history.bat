:: Windows Clipboard History Collector (User Context)
:: Companion to win_IR.bat - run separately in the subject user's session
:: By Jeremy Brice
:: forensics@cyberbyteconsulting.com
:: Updated: 2026-08-04

@echo OFF
setlocal enabledelayedexpansion

echo.
echo  ================================================================
echo   CLIPBOARD HISTORY COLLECTION - USER CONTEXT
echo  ================================================================
echo   This script must run as the subject user, NOT elevated.
echo   Clipboard history is per-user and per-session; running under
echo   any other account returns that account's data or nothing.
echo.

:: Elevation check - elevation is a FAILURE condition for this script
net session >nul 2>&1
if %errorlevel% equ 0 (
    echo  [31m WARNING: This console is running with administrator privileges. [0m
    echo  [31m If UAC was satisfied with separate admin credentials, you are   [0m
    echo  [31m about to collect the ADMIN account's clipboard, not the subject's.[0m
    echo.
    set "e="
    set /P e=[33m Continue anyway? [Y/N]: [0m
    if /I not "!e!" EQU "Y" goto :abort
)

:: Confirm identity before proceeding
echo  Executing account : %USERDOMAIN%\%USERNAME%
for /f "tokens=2 delims==" %%A in ('wmic computersystem get username /value 2^>nul ^| find "="') do set "console_user=%%A"
echo  Console user      : !console_user!
echo  Hostname          : %COMPUTERNAME%
echo.
set "ok="
set /P ok=[33m Is %USERDOMAIN%\%USERNAME% the account under investigation? [Y/N]: [0m
if /I not "%ok%" EQU "Y" goto :abort

:: Output location - must match the win_IR.bat destination
echo.
set /p output_drive=Drive letter for output [ex. D] (leave blank for %~d0\):
if "%output_drive%"=="" set "output_drive=%~d0"

:trim
set "LAST_CHAR=!output_drive:~-1!"
if "!LAST_CHAR!"=="\" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"=="/" set "output_drive=!output_drive:~0,-1!" & goto trim
if "!LAST_CHAR!"==":" set "output_drive=!output_drive:~0,-1!" & goto trim

set "output_dir=%output_drive%:\%COMPUTERNAME%"
set "clip_dir=%output_dir%\vol_data\clipboard_%USERNAME%"

:: Create tree if win_IR.bat has not run yet; harmless if it has
if not exist "%output_dir%"                 mkdir "%output_dir%"                 2>nul
if not exist "%output_dir%\vol_data"        mkdir "%output_dir%\vol_data"        2>nul
if not exist "%clip_dir%"                   mkdir "%clip_dir%"                   2>nul

if not exist "%clip_dir%" (
    echo  [31m ERROR: Cannot create "%clip_dir%" - check drive letter and write permissions. [0m
    goto :abort
)

echo %date%-%time%: Started Clipboard acquisition as %USERDOMAIN%\%USERNAME% >> "%output_dir%\log.txt"
echo Hostname: %COMPUTERNAME% >> "%clip_dir%\_context.txt"
echo Executing account: %USERDOMAIN%\%USERNAME% >> "%clip_dir%\_context.txt"
echo Console user: !console_user! >> "%clip_dir%\_context.txt"
echo Collection time (local): %date% %time% >> "%clip_dir%\_context.txt"
whoami /all >> "%clip_dir%\_context.txt" 2>&1

:: --- Registry state ---------------------------------------------------------
echo Collecting clipboard feature state
reg query "HKCU\Software\Microsoft\Clipboard" >> "%clip_dir%\clipboard_settings.txt" 2>&1

:: --- Service host PID for memory correlation --------------------------------
echo Collecting cbdhsvc process context
tasklist /svc /fi "imagename eq svchost.exe" | findstr /i cbdhsvc >> "%clip_dir%\clipboard_cbdhsvc_pid.txt" 2>&1
tasklist /fi "imagename eq rdpclip.exe" >> "%clip_dir%\clipboard_rdpclip.txt" 2>&1

:: --- Pinned items (own profile only - no admin rights) ----------------------
echo Collecting pinned clipboard items
if exist "%LOCALAPPDATA%\Microsoft\Windows\Clipboard" (
    robocopy "%LOCALAPPDATA%\Microsoft\Windows\Clipboard" "%clip_dir%\pinned" /E /COPY:DAT /R:0 /W:0 /NFL /NDL /NJH /NJS >nul 2>&1
) else (
    echo No pinned clipboard directory present for %USERNAME%. >> "%clip_dir%\clipboard_collection_log.txt"
)

:: --- Live history via WinRT -------------------------------------------------
echo.
echo  [33m Do not click away from this window during collection.       [0m
echo  [33m The WinRT API requires the calling console to be foreground. [0m
echo.
timeout /t 3 >nul

powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0TOOLS\Vol_Acquisition\Get-ClipHistory.ps1" -OutputDir "%clip_dir%" >> "%clip_dir%\clipboard_collection_log.txt" 2>&1
set "ps_rc=%errorlevel%"

if "%ps_rc%"=="0" (
    echo  [32m Clipboard history retrieved. [0m
    echo %date%-%time%: Clipboard history retrieved for %USERNAME% >> "%output_dir%\log.txt"
) else (
    echo  [31m Clipboard history NOT retrieved ^(exit %ps_rc%^). [0m
    echo  See "%clip_dir%\clipboard_collection_log.txt"
    echo %date%-%time%: Clipboard history FAILED for %USERNAME% ^(exit %ps_rc%^) >> "%output_dir%\log.txt"
)

echo.
echo  [32m %date%-%time%: Completed Clipboard Acquisition [0m
echo  Output: %clip_dir%
echo %date%-%time%: Completed Clipboard acquisition >> "%output_dir%\log.txt"
pause
exit /b 0

:abort
echo.
echo  [31m Aborted. No data collected. [0m
pause
exit /b 1
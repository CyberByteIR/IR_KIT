<#
    Clipboard History Collector
    Called by win_IR.bat
    Windows PowerShell 5.1 required. Windows 10 1809+ only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDir
)

$ErrorActionPreference = 'Stop'
function Log($m) { "{0}  {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $m }

Log "Clipboard history collection started"

# --- Context validation -----------------------------------------------------
$runAs    = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$console  = (Get-CimInstance Win32_ComputerSystem).UserName
$sessionId = (Get-Process -Id $PID).SessionId

Log "Running as        : $runAs"
Log "Console user      : $console"
Log "Session ID        : $sessionId"
Log "PowerShell version: $($PSVersionTable.PSVersion)"

if ($console -and ($runAs -ne $console)) {
    Log "WARNING: Executing account does not match the interactively logged-on user."
    Log "WARNING: Clipboard history is per-user and per-session. Output below, if any,"
    Log "WARNING: belongs to $runAs and NOT to $console. Treat accordingly."
}

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Log "ABORT: Windows PowerShell 5.1 required. WinRT projection unavailable."
    exit 2
}

# --- WinRT plumbing ---------------------------------------------------------
try {
    [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel, ContentType=WindowsRuntime] | Out-Null
    [Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResult, Windows.ApplicationModel, ContentType=WindowsRuntime] | Out-Null
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
} catch {
    Log "ABORT: Could not load WinRT types. $($_.Exception.Message)"
    exit 3
}

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                   $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($op, $type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    if (-not $t.Wait(15000)) { throw "WinRT call timed out after 15s" }
    $t.Result
}

# --- Retrieval (retry: foreground focus can be transiently lost) ------------
$result = $null
foreach ($attempt in 1..3) {
    try {
        $result = Await ([Windows.ApplicationModel.DataTransfer.Clipboard]::GetHistoryItemsAsync()) `
                        ([Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResult])
        Log "Attempt $attempt status: $($result.Status)"
        if ($result.Status -eq 'Success') { break }
    } catch {
        Log "Attempt $attempt exception: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 2
}

if (-not $result -or $result.Status -ne 'Success') {
    Log "RESULT: No history retrieved. Status = $(if($result){$result.Status}else{'no response'})"
    Log "  AccessDenied            -> non-interactive/remote session, or console not foreground"
    Log "  ClipboardHistoryDisabled-> feature off (see clipboard_settings.txt)"
    Log "Fall back to carving cbdhsvc from the memory image."
    exit 1
}

# --- Extraction -------------------------------------------------------------
$rows = foreach ($i in $result.Items) {
    $text = $null
    $html = $null
    try { if ($i.Content.AvailableFormats -contains 'Text')        { $text = Await ($i.Content.GetTextAsync()) ([string]) } } catch {}
    try { if ($i.Content.AvailableFormats -contains 'HTML Format') { $html = Await ($i.Content.GetHtmlFormatAsync()) ([string]) } } catch {}
    [pscustomobject]@{
        Id            = $i.Id
        TimestampUtc  = $i.Timestamp.UtcDateTime.ToString('o')
        TimestampLocal= $i.Timestamp.LocalDateTime.ToString('o')
        Formats       = ($i.Content.AvailableFormats -join ';')
        TextLength    = if ($text) { $text.Length } else { 0 }
        Text          = $text
        HtmlFormat    = $html
    }
}

Log "Items returned: $($rows.Count)"

$csv = Join-Path $OutputDir 'clipboard_history.csv'
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv

$h = (Get-FileHash $csv -Algorithm SHA256).Hash
Log "Wrote  : $csv"
Log "SHA256 : $h"
Log "NOTE: Image/bitmap entries are recorded by format only; binary payload not exported."
Log "NOTE: Items flagged ExcludeClipboardContentFromMonitorProcessing are filtered by this API."
Log "Clipboard history collection completed"
exit 0
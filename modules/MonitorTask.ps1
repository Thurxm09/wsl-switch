param([int]$ThresholdPct = 80, [int]$CooldownMin = 30)

$scriptDir    = $PSScriptRoot
$cooldownFile = Join-Path $scriptDir "..\data\monitor_cooldown.txt"

$vmmem = Get-Process -Name "vmmem" -ErrorAction SilentlyContinue
if (-not $vmmem) { exit 0 }

$os        = Get-CimInstance Win32_OperatingSystem
$totalKB   = $os.TotalVisibleMemorySize
$usedByWsl = [math]::Round($vmmem.WorkingSet64 / 1KB, 0)
$pct       = [math]::Round($usedByWsl / $totalKB * 100, 0)

if ($pct -lt $ThresholdPct) { exit 0 }

if (Test-Path $cooldownFile) {
    $lastAlert = [datetime]::ParseExact(
        (Get-Content $cooldownFile -Raw).Trim(),
        "yyyy-MM-dd HH:mm:ss", $null
    )
    if ((New-TimeSpan -Start $lastAlert -End (Get-Date)).TotalMinutes -lt $CooldownMin) { exit 0 }
}

(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Set-Content $cooldownFile -Encoding ASCII

$usedGB  = [math]::Round($vmmem.WorkingSet64 / 1GB, 1)
$totalGB = [math]::Round($totalKB / 1MB, 1)
$appId   = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"

$xml = "<toast><visual><binding template='ToastGeneric'>" +
       "<text>WSL2 - Alerte memoire</text>" +
       "<text>RAM : $pct% utilise ($usedGB GB / $totalGB GB)</text>" +
       "<text>Pensez a switcher vers un profil plus leger.</text>" +
       "</binding></visual></toast>"

try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
    $doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $doc.LoadXml($xml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
} catch {
    $logPath = Join-Path $scriptDir "..\data\monitor_errors.txt"
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Toast error : $_" | Add-Content $logPath -Encoding ASCII
}

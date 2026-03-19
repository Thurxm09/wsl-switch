# WeeklyReport.ps1
# Genere un rapport hebdomadaire depuis history.json.
# Peut etre appele manuellement ou par tache planifiee.

param([switch]$Silent)

$historyPath = Join-Path $PSScriptRoot "..\data\history.json"
$reportsDir  = Join-Path $PSScriptRoot "..\data\reports"

if (-not (Test-Path $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir | Out-Null
}

if (-not (Test-Path $historyPath)) {

# Rotation : on garde les 12 derniers rapports
$allReports = Get-ChildItem $reportsDir -Filter "report_*.txt" | Sort-Object Name
if ($allReports.Count -gt 12) {
    $allReports | Select-Object -First ($allReports.Count - 12) | Remove-Item -Force
}
    if (-not $Silent) { Write-Host "  Aucun historique disponible." -ForegroundColor Gray }
    exit 0
}

$history = @(Get-Content $historyPath -Raw | ConvertFrom-Json)
if ($history.Count -eq 0) {
    if (-not $Silent) { Write-Host "  Historique vide." -ForegroundColor Gray }
    exit 0
}

$weekAgo = (Get-Date).AddDays(-7)

$switches = $history | Where-Object {
    $_.action -eq "SWITCH" -and
    [datetime]::ParseExact($_.timestamp, "yyyy-MM-dd HH:mm:ss", $null) -ge $weekAgo
}

$switches = @($switches)

# ---- Construction du rapport ----------------------------------------

$lines = @()
$lines += "WSL2 Profile Switcher - Rapport hebdomadaire"
$lines += "Genere le : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "Periode   : $($weekAgo.ToString('yyyy-MM-dd')) -> $(Get-Date -Format 'yyyy-MM-dd')"
$lines += "=" * 50

if ($switches.Count -eq 0) {
    $lines += ""
    $lines += "Aucun switch enregistre cette semaine."
    $lines += ""
} else {
    # Repartition par profil
    $lines += ""
    $lines += "Repartition par profil :"
    $lines += "-" * 30

    $grouped = $switches | Group-Object -Property profile | Sort-Object Count -Descending

    $dominant = $grouped | Select-Object -First 1
    $total    = $switches.Count

    foreach ($g in $grouped) {
        $pct = [math]::Round($g.Count / $total * 100, 0)
        $bar = "#" * [math]::Round($pct / 5)
        $lines += ("  " + $g.Name.PadRight(16) + $bar.PadRight(20) + " $($g.Count)x ($pct%)")
    }

    $lines += ""
    $lines += "Profil dominant   : $($dominant.Name.ToUpper()) ($($dominant.Count) activations)"
    $lines += "Total de switchs  : $total"

    # Jours les plus actifs
    $byDay = $switches | Group-Object {
        [datetime]::ParseExact($_.timestamp, "yyyy-MM-dd HH:mm:ss", $null).DayOfWeek
    } | Sort-Object Count -Descending | Select-Object -First 1

    if ($byDay) {
        $lines += "Jour le plus actif: $($byDay.Name) ($($byDay.Count) switchs)"
    }

    # Heure de pointe
    $byHour = $switches | Group-Object {
        [datetime]::ParseExact($_.timestamp, "yyyy-MM-dd HH:mm:ss", $null).Hour
    } | Sort-Object Count -Descending | Select-Object -First 1

    if ($byHour) {
        $lines += "Heure de pointe   : $($byHour.Name)h00 ($($byHour.Count) switchs)"
    }

    $lines += ""
    $lines += "-" * 30

    # Derniers switchs
    $lines += ""
    $lines += "Derniers switchs (5) :"
    $last5 = $switches | Select-Object -Last 5
    foreach ($e in $last5) {
        $lines += ("  " + $e.timestamp + "  " + $e.profile.PadRight(14) + $e.details)
    }
}

# Alertes monitoring si disponibles
$cooldown = Join-Path $PSScriptRoot "..\data\monitor_cooldown.txt"
if (Test-Path $cooldown) {
    $lastAlert = (Get-Content $cooldown -Raw).Trim()
    $lines += ""
    $lines += "Derniere alerte RAM : $lastAlert"
}

$errors = Join-Path $PSScriptRoot "..\data\monitor_errors.txt"
if (Test-Path $errors) {
    $errCount = (Get-Content $errors).Count
    if ($errCount -gt 0) {
        $lines += "Erreurs Toast       : $errCount (voir data\monitor_errors.txt)"
    }
}

$lines += ""
$lines += "=" * 50
$lines += "Fin du rapport."

# ---- Ecriture du fichier --------------------------------------------

$reportName = "report_" + (Get-Date -Format "yyyy-MM-dd") + ".txt"
$reportPath = Join-Path $reportsDir $reportName

$lines | Set-Content $reportPath -Encoding ASCII

if (-not $Silent) {
    Write-Host ""
    Write-Host "  Rapport genere : $reportPath" -ForegroundColor Green
    Write-Host ""
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""
}


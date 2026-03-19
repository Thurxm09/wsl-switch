$TASK_NAME = "WSL2-RamMonitor"

function Start-WslMonitor {
    param([int]$ThresholdPct = 80, [int]$CooldownMin = 30)

    $taskScript = Join-Path $Global:WSLRoot "modules\MonitorTask.ps1"
    if (-not (Test-Path $taskScript)) {
        Write-Host "  ERREUR : MonitorTask.ps1 introuvable." -ForegroundColor Red
        return
    }

    $existing = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false }

    $psArgs  = "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass " +
               "-File `"$taskScript`" -ThresholdPct $ThresholdPct -CooldownMin $CooldownMin"
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs
    $trigger  = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 1) -Once -At (Get-Date)
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $TASK_NAME -Action $action -Trigger $trigger `
        -Settings $settings -RunLevel Highest -Force | Out-Null

    Write-Host ""
    Write-Host "  Monitoring demarre." -ForegroundColor Green
    Write-Host "  Seuil  : $ThresholdPct% RAM" -ForegroundColor Gray
    Write-Host "  Cooldown : alerte max toutes les $CooldownMin min" -ForegroundColor Gray
    Write-Host "  Mode   : tache planifiee Windows (sans terminal)" -ForegroundColor Gray
    Write-Host ""
}

function Stop-WslMonitor {
    $existing = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "  Le monitoring n'est pas actif." -ForegroundColor Gray
        return
    }
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
    Write-Host "  Monitoring arrete." -ForegroundColor Yellow
    Write-Host ""
}

function Get-MonitorStatus {
    $task     = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    $cooldown = Join-Path $Global:WSLRoot "data\monitor_cooldown.txt"
    $errors   = Join-Path $Global:WSLRoot "data\monitor_errors.txt"
    Write-Host ""
    if ($task) {
        $sc = switch ($task.State) { "Running"{"Green"} "Ready"{"Cyan"} default{"Gray"} }
        Write-Host "  Monitoring    : ACTIF ($($task.State))" -ForegroundColor $sc
    } else {
        Write-Host "  Monitoring    : INACTIF" -ForegroundColor DarkGray
    }
    $last = if (Test-Path $cooldown) { (Get-Content $cooldown -Raw).Trim() } else { "aucune" }
    Write-Host "  Derniere alerte : $last" -ForegroundColor Gray
    if ((Test-Path $errors) -and ((Get-Content $errors).Count -gt 0)) {
        Write-Host "  Erreurs toast : voir data\monitor_errors.txt" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

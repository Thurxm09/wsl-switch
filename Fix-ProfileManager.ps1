# Fix-ProfileManager.ps1
# Reecrit ProfileManager.ps1 entierement.
# Corrige aussi le probleme swapFile via slashes forward.
# Usage : .\Fix-ProfileManager.ps1

$root = "C:\Scripts\WSL-Switch"

$profileManager = @'
# ============================================================
#  ProfileManager.ps1 - Gestion des profils WSL2
#  Dot-source depuis wsl-switch.ps1
#  Utilise $Global:WSLRoot defini dans le script principal
# ============================================================

function Get-ProfilesPath  { Join-Path $Global:WSLRoot "data\profiles.json" }
function Get-BackupPath    { Join-Path $Global:WSLRoot "data\wslconfig.backup" }
function Get-WslConfigPath { Join-Path $env:USERPROFILE ".wslconfig" }

# ---- Lecture de la configuration ------------------------------------

function Get-ProfileConfig {
    $path = Get-ProfilesPath
    if (-not (Test-Path $path)) {
        Write-Host ""
        Write-Host "  ERREUR : profiles.json introuvable." -ForegroundColor Red
        Write-Host "  Chemin attendu : $path" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
    $raw = Get-Content $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Host ""
        Write-Host "  ERREUR : profiles.json est vide." -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        Write-Host ""
        Write-Host "  ERREUR : profiles.json est corrompu (JSON invalide)." -ForegroundColor Red
        Write-Host "  Detail : $_" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
    if ($null -eq $parsed.profiles) {
        Write-Host ""
        Write-Host "  ERREUR : profiles.json incomplet - cle manquante : profiles" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    return $parsed
}

function Get-ActiveProfile {
    $wslConfig = Get-WslConfigPath
    if (-not (Test-Path $wslConfig)) {
        return [PSCustomObject]@{ name = "Non configure"; key = ""; memory = "N/A"; processors = "?" }
    }
    $lines = Get-Content $wslConfig -Encoding UTF8
    $mem   = ($lines | Where-Object { $_ -match "^memory=" }     | Select-Object -First 1) -replace "memory=", ""
    $cpu   = ($lines | Where-Object { $_ -match "^processors=" } | Select-Object -First 1) -replace "processors=", ""
    try {
        $config  = Get-ProfileConfig
        $matched = $config.profiles.PSObject.Properties |
                   Where-Object { $_.Value.memory -eq $mem } |
                   Select-Object -First 1
        return [PSCustomObject]@{
            name       = if ($matched) { $matched.Value.displayName } else { "Personnalise" }
            key        = if ($matched) { $matched.Name } else { "custom" }
            memory     = $mem
            processors = $cpu
        }
    } catch {
        return [PSCustomObject]@{ name = "?"; key = ""; memory = $mem; processors = $cpu }
    }
}

# ---- Integrite & backup ---------------------------------------------

function Test-WslConfigIntegrity {
    $wslConfig = Get-WslConfigPath
    if (-not (Test-Path $wslConfig)) { return $false }
    $content  = Get-Content $wslConfig -Raw -Encoding UTF8
    $required = @("[wsl2]", "memory=", "processors=")
    foreach ($key in $required) {
        if ($content -notmatch [regex]::Escape($key)) {
            Write-Warning "Cle manquante dans .wslconfig : $key"
            return $false
        }
    }
    return $true
}

function Backup-WslConfig {
    $src = Get-WslConfigPath
    if (Test-Path $src) { Copy-Item $src (Get-BackupPath) -Force }
}

function Invoke-Rollback {
    $backupPath = Get-BackupPath
    if (-not (Test-Path $backupPath)) {
        Write-Host ""
        Write-Host "  Aucun backup disponible - rollback impossible." -ForegroundColor Red
        Write-Host ""
        return
    }
    Write-Host ""
    Write-Host "  Rollback en cours..." -ForegroundColor Yellow
    Write-Host "  Arret de WSL2..." -ForegroundColor Gray
    wsl --shutdown
    Start-Sleep -Seconds 2
    Copy-Item $backupPath (Get-WslConfigPath) -Force
    Write-Host "  .wslconfig restaure." -ForegroundColor Green
    $restored = Get-ActiveProfile
    Write-Host "  Profil restaure : $($restored.name) ($($restored.memory) / $($restored.processors) CPU)" -ForegroundColor Cyan
    Write-Host ""
    Write-SwitchLog -Action "ROLLBACK" -Profile $restored.key -Details "Restaure depuis backup"
}

# ---- Generation & application ---------------------------------------
# Note : swapFile utilise des slashes forward (C:/Temp/...)
# WSL2 et Windows acceptent les deux formats dans .wslconfig
# Cela evite le probleme d'echappement du backslash

function ConvertTo-WslConfigContent {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)
    $swapFile = $Profile.swapFile
    return @"
[wsl2]
memory=$($Profile.memory)
processors=$($Profile.processors)
swap=$($Profile.swap)
swapFile=$swapFile
kernelCommandLine=sysctl.vm.swappiness=$($Profile.swappiness)
"@
}

function Set-WslProfile {
    param(
        [Parameter(Mandatory)][string]$Key,
        [switch]$DryRun
    )
    $config = Get-ProfileConfig
    $prop   = $config.profiles.PSObject.Properties | Where-Object { $_.Name -eq $Key }
    if ($null -eq $prop) {
        throw "Profil '$Key' introuvable. Profils disponibles : $($config.profiles.PSObject.Properties.Name -join ', ')"
    }
    $profile = $prop.Value
    $content = ConvertTo-WslConfigContent -Profile $profile

    if ($DryRun) {
        Write-Host ""
        Write-Host "  DRY-RUN - Simulation (aucune ecriture)" -ForegroundColor DarkYellow
        Write-Host "  Profil  : $($profile.displayName)" -ForegroundColor Yellow
        Write-Host "  Memoire : $($profile.memory)" -ForegroundColor Gray
        Write-Host "  CPU     : $($profile.processors)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Contenu .wslconfig simule :" -ForegroundColor DarkGray
        $content -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Host ""
        return
    }

    Backup-WslConfig
    Write-Host ""
    Write-Host "  Activation du profil $($profile.displayName)..." -ForegroundColor $profile.color
    Write-Host "  Arret de WSL2..." -ForegroundColor Gray
    wsl --shutdown
    Start-Sleep -Seconds 2
    Set-Content -Path (Get-WslConfigPath) -Value $content -Encoding UTF8

    if (-not (Test-WslConfigIntegrity)) {
        Write-Host "  ERREUR : .wslconfig invalide apres ecriture. Rollback automatique." -ForegroundColor Red
        Invoke-Rollback
        return
    }

    Write-Host "  OK - $($profile.displayName) actif - $($profile.memory) / $($profile.processors) CPU" -ForegroundColor Green
    Write-Host "  WSL2 demarrera avec ce profil au prochain lancement." -ForegroundColor DarkGray
    Write-Host ""
    Write-SwitchLog -Action "SWITCH" -Profile $Key -Details "$($profile.memory), $($profile.processors) CPU"
}

# ---- Profils personnalises ------------------------------------------

function New-CustomProfile {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Memory,
        [Parameter(Mandatory)][int]$Processors,
        [string]$Description = "Profil personnalise",
        [string]$Swap        = "2GB",
        [int]$Swappiness     = 10
    )
    if ($Memory -notmatch "^\d+GB$") {
        throw "Format memoire invalide : '$Memory'. Attendu : ex. 4GB, 8GB, 12GB"
    }
    if ($Processors -lt 1 -or $Processors -gt 8) {
        throw "Nombre de CPU invalide : $Processors. Attendu : entre 1 et 8"
    }
    $config     = Get-ProfileConfig
    $newProfile = [PSCustomObject]@{
        displayName = $Key.ToUpper()
        description = $Description
        color       = "Magenta"
        memory      = $Memory
        processors  = $Processors
        swap        = $Swap
        swapFile    = "C:/Temp/wsl-swap.vhdx"
        swappiness  = $Swappiness
    }
    $config.profiles | Add-Member -MemberType NoteProperty -Name $Key.ToLower() -Value $newProfile -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content (Get-ProfilesPath) -Encoding UTF8
    Write-Host "  OK - Profil '$($Key.ToUpper())' cree ($Memory / $Processors CPU)." -ForegroundColor Green
    Write-SwitchLog -Action "CUSTOM" -Profile $Key.ToLower() -Details "Cree : $Memory, $Processors CPU"
}

function Export-Profiles {
    param([string]$Path = ".\wsl-profiles-export.json")
    Copy-Item (Get-ProfilesPath) $Path -Force
    Write-Host "  OK - Profils exportes vers : $Path" -ForegroundColor Green
    Write-SwitchLog -Action "EXPORT" -Details $Path
}

function Import-Profiles {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Fichier introuvable : $Path" }
    try { Get-Content $Path -Raw | ConvertFrom-Json | Out-Null }
    catch { throw "JSON invalide : $Path - $_" }
    Backup-WslConfig
    Copy-Item $Path (Get-ProfilesPath) -Force
    Write-Host "  OK - Profils importes depuis : $Path" -ForegroundColor Green
    Write-SwitchLog -Action "IMPORT" -Details $Path
}
'@

# Correction profiles.json : slashes forward pour swapFile
$profilesJson = @'
{
  "version": "2.0",
  "profiles": {
    "web": {
      "displayName": "WEB",
      "description": "Brave + VS Code + WSL leger",
      "color": "Green",
      "memory": "2GB",
      "processors": 3,
      "swap": "3GB",
      "swapFile": "C:/Temp/wsl-swap.vhdx",
      "swappiness": 10
    },
    "data": {
      "displayName": "DATA SCIENCE",
      "description": "Jupyter + Pandas + ML",
      "color": "Yellow",
      "memory": "6GB",
      "processors": 5,
      "swap": "2GB",
      "swapFile": "C:/Temp/wsl-swap.vhdx",
      "swappiness": 10
    },
    "base": {
      "displayName": "BASE",
      "description": "Mode minimal - conservation RAM",
      "color": "Cyan",
      "memory": "1GB",
      "processors": 2,
      "swap": "1GB",
      "swapFile": "C:/Temp/wsl-swap.vhdx",
      "swappiness": 20
    }
  },
  "settings": {
    "monitorThreshold": 80,
    "monitorIntervalSeconds": 30,
    "historyMaxEntries": 100,
    "backupEnabled": true
  }
}
'@

Set-Content "$root\modules\ProfileManager.ps1" -Value $profileManager -Encoding ASCII
Write-Host "  [OK] ProfileManager.ps1 reecrit." -ForegroundColor Green

Set-Content "$root\data\profiles.json" -Value $profilesJson -Encoding ASCII
Write-Host "  [OK] profiles.json - swapFile en slashes forward." -ForegroundColor Green

Write-Host ""
Write-Host "  Relance le menu pour verifier :" -ForegroundColor Gray
Write-Host "  wsl-switch" -ForegroundColor Gray
Write-Host ""

# ============================================================
#  ProfileManager.ps1 ? Gestion des profils WSL2
#  Dot-sourc? depuis wsl-switch.ps1
#  Utilise $Global:WSLRoot d?fini dans le script principal
# ============================================================

function Get-ProfilesPath  { Join-Path $Global:WSLRoot "data\profiles.json" }
function Get-BackupPath    { Join-Path $Global:WSLRoot "data\wslconfig.backup" }
function Get-WslConfigPath { Join-Path $env:USERPROFILE ".wslconfig" }

# ??? Lecture de la configuration ????????????????????????????

function Get-ProfileConfig {
    <#
    .SYNOPSIS
        Charge profiles.json et retourne l'objet de configuration.
    .OUTPUTS
        PSCustomObject ? structure compl?te du JSON
    #>
    $path = Get-ProfilesPath
    if (-not (Test-Path $path)) {
        throw "profiles.json introuvable : $path"
    }
    try {
        return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "profiles.json illisible ou corrompu : $_"
    }
}

function Get-ActiveProfile {
    <#
    .SYNOPSIS
        Lit .wslconfig et identifie le profil actif par correspondance m?moire.
    .OUTPUTS
        PSCustomObject { name, key, memory, processors }
    #>
    $wslConfig = Get-WslConfigPath

    if (-not (Test-Path $wslConfig)) {
        return [PSCustomObject]@{ name = "Non configur?"; key = ""; memory = "N/A"; processors = "?" }
    }

    $lines = Get-Content $wslConfig -Encoding UTF8
    $mem   = ($lines | Where-Object { $_ -match "^memory=" }     | Select-Object -First 1) -replace "memory=", ""
    $cpu   = ($lines | Where-Object { $_ -match "^processors=" } | Select-Object -First 1) -replace "processors=", ""

    # R?solution nom <-> profil connu
    try {
        $config  = Get-ProfileConfig
        $matched = $config.profiles.PSObject.Properties |
                   Where-Object { $_.Value.memory -eq $mem } |
                   Select-Object -First 1

        return [PSCustomObject]@{
            name       = if ($matched) { $matched.Value.displayName } else { "Personnalis?" }
            key        = if ($matched) { $matched.Name } else { "custom" }
            memory     = $mem
            processors = $cpu
        }
    }
    catch {
        return [PSCustomObject]@{ name = "?"; key = ""; memory = $mem; processors = $cpu }
    }
}

# ??? Int?grit? & backup ??????????????????????????????????????

function Test-WslConfigIntegrity {
    <#
    .SYNOPSIS
        V?rifie que .wslconfig contient les cl?s minimales attendues.
    .OUTPUTS
        [bool]
    #>
    $wslConfig = Get-WslConfigPath
    if (-not (Test-Path $wslConfig)) { return $false }

    $content  = Get-Content $wslConfig -Raw -Encoding UTF8
    $required = @("[wsl2]", "memory=", "processors=")

    foreach ($key in $required) {
        if ($content -notmatch [regex]::Escape($key)) {
            Write-Warning "Cl? manquante dans .wslconfig : $key"
            return $false
        }
    }
    return $true
}

function Backup-WslConfig {
    <#
    .SYNOPSIS
        Copie .wslconfig vers le fichier backup avant toute modification.
    #>
    $src = Get-WslConfigPath
    if (Test-Path $src) {
        Copy-Item $src (Get-BackupPath) -Force
    }
}

function Invoke-Rollback {
    <#
    .SYNOPSIS
        Restaure .wslconfig depuis le backup et red?marre WSL2.
    #>
    $backupPath = Get-BackupPath

    if (-not (Test-Path $backupPath)) {
        Write-Host ""
        Write-Host "  Aucun backup disponible ? rollback impossible." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  ?  Rollback en cours..." -ForegroundColor Yellow
    Write-Host "  Arr?t de WSL2..." -ForegroundColor Gray
    wsl --shutdown
    Start-Sleep -Seconds 2

    Copy-Item $backupPath (Get-WslConfigPath) -Force
    Write-Host "  ?  .wslconfig restaur?." -ForegroundColor Green

    $restored = Get-ActiveProfile
    Write-Host "  Profil restaur? : $($restored.name) ($($restored.memory) / $($restored.processors) CPU)" -ForegroundColor Cyan
    Write-Host ""

    Write-SwitchLog -Action "ROLLBACK" -Profile $restored.key -Details "Restaur? depuis backup"
}

# ??? G?n?ration & application ????????????????????????????????

function ConvertTo-WslConfigContent {
    <#
    .SYNOPSIS
        G?n?re la cha?ne texte d'un .wslconfig depuis un objet profil.
    #>
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    return @"
[wsl2]
memory=$($Profile.memory)
processors=$($Profile.processors)
swap=$($Profile.swap)
swapFile=$($Profile.swapFile)
kernelCommandLine=sysctl.vm.swappiness=$($Profile.swappiness)
"@
}

function Set-WslProfile {
    <#
    .SYNOPSIS
        Applique un profil WSL2.
        Backup automatique, validation post-?criture, rollback si invalide.
    .PARAMETER Key
        Cl? du profil (ex : "web", "data", "base")
    .PARAMETER DryRun
        Simule l'application sans toucher au syst?me
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [switch]$DryRun
    )

    $config = Get-ProfileConfig
    $prop   = $config.profiles.PSObject.Properties | Where-Object { $_.Name -eq $Key }

    if ($null -eq $prop) {
        throw "Profil '$Key' introuvable dans profiles.json. Profils disponibles : $($config.profiles.PSObject.Properties.Name -join ', ')"
    }

    $profile = $prop.Value
    $content = ConvertTo-WslConfigContent -Profile $profile

    # ?? Mode simulation ??
    if ($DryRun) {
        Write-Host ""
        Write-Host "  ??? DRY-RUN ? Simulation (aucune ?criture) ???" -ForegroundColor DarkYellow
        Write-Host "  ?  Profil  : $($profile.displayName)" -ForegroundColor Yellow
        Write-Host "  ?  M?moire : $($profile.memory)" -ForegroundColor Gray
        Write-Host "  ?  CPU     : $($profile.processors)" -ForegroundColor Gray
        Write-Host "  ?" -ForegroundColor DarkYellow
        Write-Host "  ?  Contenu .wslconfig simul? :" -ForegroundColor DarkGray
        $content -split "`n" | ForEach-Object {
            Write-Host "  ?    $_" -ForegroundColor DarkGray
        }
        Write-Host "  ??????????????????????????????????????????????" -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    # ?? Application r?elle ??
    Backup-WslConfig

    Write-Host ""
    Write-Host "  Activation du profil $($profile.displayName)..." -ForegroundColor $profile.color
    Write-Host "  Arr?t de WSL2..." -ForegroundColor Gray
    wsl --shutdown
    Start-Sleep -Seconds 2

    Set-Content -Path (Get-WslConfigPath) -Value $content -Encoding UTF8

    # Validation post-?criture ? rollback automatique si probl?me
    if (-not (Test-WslConfigIntegrity)) {
        Write-Host "  ERREUR : .wslconfig invalide apr?s ?criture. Rollback automatique." -ForegroundColor Red
        Invoke-Rollback
        return
    }

    Write-Host "  ? $($profile.displayName) actif ? $($profile.memory) / $($profile.processors) CPU" -ForegroundColor Green
    Write-Host "  WSL2 d?marrera avec ce profil au prochain lancement." -ForegroundColor DarkGray
    Write-Host ""

    Write-SwitchLog -Action "SWITCH" -Profile $Key -Details "$($profile.memory), $($profile.processors) CPU"
}

# ??? Gestion des profils personnalis?s ???????????????????????

function New-CustomProfile {
    <#
    .SYNOPSIS
        Cr?e un profil personnalis? et l'ajoute ? profiles.json.
    .EXAMPLE
        New-CustomProfile -Key "perf" -Memory "10GB" -Processors 4 -Description "Mode performance"
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Memory,
        [Parameter(Mandatory)][int]$Processors,
        [string]$Description = "Profil personnalis?",
        [string]$Swap        = "2GB",
        [int]$Swappiness     = 10
    )

    # Validation basique de la m?moire
    if ($Memory -notmatch "^\d+GB$") {
        throw "Format m?moire invalide : '$Memory'. Attendu : ex. 4GB, 8GB, 12GB"
    }
    if ($Processors -lt 1 -or $Processors -gt 8) {
        throw "Nombre de CPU invalide : $Processors. Attendu : entre 1 et 8 pour un i5"
    }

    $config = Get-ProfileConfig

    $newProfile = [PSCustomObject]@{
        displayName = $Key.ToUpper()
        description = $Description
        color       = "Magenta"
        memory      = $Memory
        processors  = $Processors
        swap        = $Swap
        swapFile    = "C:\Temp\wsl-swap.vhdx"
        swappiness  = $Swappiness
    }

    $config.profiles | Add-Member -MemberType NoteProperty -Name $Key.ToLower() -Value $newProfile -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content (Get-ProfilesPath) -Encoding UTF8

    Write-Host "  ? Profil '$($Key.ToUpper())' cr?? ($Memory / $Processors CPU)." -ForegroundColor Green
    Write-SwitchLog -Action "CUSTOM" -Profile $Key.ToLower() -Details "Cr?? : $Memory, $Processors CPU"
}

function Export-Profiles {
    <#
    .SYNOPSIS
        Exporte profiles.json vers un chemin cible (portabilit? / sauvegarde).
    #>
    param([string]$Path = ".\wsl-profiles-export.json")

    Copy-Item (Get-ProfilesPath) $Path -Force
    Write-Host "  ? Profils export?s vers : $Path" -ForegroundColor Green
    Write-SwitchLog -Action "EXPORT" -Details $Path
}

function Import-Profiles {
    <#
    .SYNOPSIS
        Importe un fichier profiles.json externe.
        Backup automatique de l'existant avant remplacement.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Fichier introuvable : $Path"
    }
    try {
        Get-Content $Path -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "JSON invalide : $Path ? $_"
    }

    Backup-WslConfig
    Copy-Item $Path (Get-ProfilesPath) -Force
    Write-Host "  ? Profils import?s depuis : $Path" -ForegroundColor Green
    Write-SwitchLog -Action "IMPORT" -Details $Path
}

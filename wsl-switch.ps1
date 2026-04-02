# ============================================================
#  WSL2 Profile Switcher v2.0 - Thuram Dev Setup
# ============================================================
#
#  USAGE
#  -----
#  .\wsl-switch.ps1                    -> menu interactif
#  .\wsl-switch.ps1 web                -> switch direct
#  .\wsl-switch.ps1 data -DryRun       -> simulation sans ecriture
#  .\wsl-switch.ps1 -Rollback          -> restauration backup
#  .\wsl-switch.ps1 -History           -> voir l'historique
#  .\wsl-switch.ps1 -NewProfile "perf 8GB 4 Description"
#  .\wsl-switch.ps1 -Export            -> exporter profils
#  .\wsl-switch.ps1 -Import path.json  -> importer profils
#  .\wsl-switch.ps1 -DebugMode         -> mode debug (erreurs visibles)
#
# ============================================================

#Requires -Version 5.1

param(
    [string]$Profil     = "",
    [switch]$DryRun,
    [switch]$Rollback,
    [switch]$History,
    [switch]$Export,
    [string]$Import     = "",
    [string]$NewProfile = "",
    [string]$Monitor    = "",
    [switch]$Report,
    [switch]$Clean,
    [switch]$Version,
    [switch]$DebugMode 
)

if ($DebugMode) {
    $ErrorActionPreference = 'Continue'   # Mode bavard pour debug
    $VerbosePreference     = 'Continue'
    Write-Host "  [DEBUG] Mode debug actif — erreurs affichées" -ForegroundColor Magenta
} else {
    $ErrorActionPreference = 'Stop'       # Mode prod : silencieux
}

# ---- Gestion des erreurs -------------------------------------------
# Doit etre defini avant tout pour capturer les erreurs des modules

if ($DebugMode) {
    $ErrorActionPreference = 'Continue'
    $VerbosePreference     = 'Continue'
    Write-Host "  [DEBUG] Mode debug actif - erreurs affichees" -ForegroundColor Magenta
} else {
    $ErrorActionPreference = 'Stop'
}

# ---- Bootstrap ------------------------------------------------------

$Global:WSLRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot "modules\ProfileManager.ps1")
. (Join-Path $PSScriptRoot "modules\Logger.ps1")
. (Join-Path $PSScriptRoot "modules\Monitor.ps1")

$dataDir = Join-Path $PSScriptRoot "data"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }

function Get-AppVersion {
    $versionFile = Join-Path $PSScriptRoot "VERSION"
    if (Test-Path $versionFile) { return (Get-Content $versionFile -Raw).Trim() }
    return "2.0.0"
}

$Global:AppVersion = Get-AppVersion

# ---- Caracteres Unicode exprimes via [char] -------------------------
# Aucun octet non-ASCII dans ce fichier source.
# Le terminal affiche les vrais glyphes ; le fichier reste ASCII pur.
#
# U+2551 : double vertical bar  ||
# U+2550 : double horizontal    ==
# U+2554 : top-left corner      [=
# U+2557 : top-right corner     =]
# U+255A : bottom-left corner   [=
# U+255D : bottom-right corner  =]
# U+2560 : left tee             |=
# U+2563 : right tee            =|
# U+2588 : full block           ##
# U+2591 : light shade          ::

$C_VERT   = [char]0x2551   # ||
$C_HORIZ  = [char]0x2550   # ==
$C_TL     = [char]0x2554   # top-left
$C_TR     = [char]0x2557   # top-right
$C_BL     = [char]0x255A   # bottom-left
$C_BR     = [char]0x255D   # bottom-right
$C_LT     = [char]0x2560   # left tee
$C_RT     = [char]0x2563   # right tee
$C_FULL   = [char]0x2588   # full block
$C_LIGHT  = [char]0x2591   # light shade
$C_DASH   = [char]0x2500   # thin horizontal dash

# Largeur interieure de la boite : 47 chars (nombre de == dans le header)
$BOX_W = 47

# Lignes de structure precalculees
$LINE_TOP = "  " + $C_TL + ([string]$C_HORIZ * $BOX_W) + $C_TR
$LINE_MID = "  " + $C_LT + ([string]$C_HORIZ * $BOX_W) + $C_RT
$LINE_BOT = "  " + $C_BL + ([string]$C_HORIZ * $BOX_W) + $C_BR
$LINE_SEP = "  " + $C_VERT + ([string]$C_DASH  * $BOX_W) + $C_VERT

# Constantes de layout pour les lignes de contenu
# Structure : "  " + $C_VERT + cursor(4) + content(43) + $C_VERT
# Total ligne : 2 + 1 + 4 + 43 + 1 = 51 == longueur de $LINE_TOP
$CURSOR_W  = 4
$CONTENT_W = $BOX_W - $CURSOR_W   # 43
$LABEL_W   = 14
$DESC_W    = 22
$MEM_W     = $CONTENT_W - $LABEL_W - $DESC_W   # 7

# ---- Utilitaires display --------------------------------------------

function Fit-String {
    param([string]$s, [int]$n)
    if ($s.Length -gt $n) { return $s.Substring(0, $n) }
    return $s.PadRight($n)
}

function Make-BoxLine {
    # Construit une ligne encadree : "  || cursor content ||"
    # Une seule string, un seul Write-Host => alignement garanti
    param([string]$cursor, [string]$content)
    return "  " + $C_VERT + $cursor + (Fit-String $content $CONTENT_W) + $C_VERT
}

function Get-RamInfo {
    try {
        $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $used  = [math]::Round($total - $free, 1)
        $pct   = [math]::Round($used / $total * 100, 0)
        return [PSCustomObject]@{ total = $total; used = $used; pct = $pct }
    }
    catch {
        if ($DebugMode) { Write-Host "  [DEBUG] Get-RamInfo : $_" -ForegroundColor DarkYellow }
        return [PSCustomObject]@{ total = 0; used = 0; pct = 0 }
    }
}

function Get-RamBar {
    param([int]$Pct)
    $filled = [math]::Round($Pct / 10)
    $empty  = 10 - $filled
    return ([string]$C_FULL * $filled) + ([string]$C_LIGHT * $empty)
}

function Show-Header {
    param([string]$ActiveName = "?", [string]$ActiveMem = "?")

    Clear-Host
    Write-Host ""

    $ram      = Get-RamInfo
    $bar      = Get-RamBar -Pct $ram.pct
    $ramColor = if ($ram.pct -ge 80) { "Red" } elseif ($ram.pct -ge 60) { "Yellow" } else { "Green" }

    Write-Host $LINE_TOP -ForegroundColor Cyan
    Write-Host (Make-BoxLine "    " "   WSL2 Profile Switcher  v$($Global:AppVersion)   ") -ForegroundColor Cyan
    Write-Host (Make-BoxLine "    " "   Thuram Dev Setup                    ") -ForegroundColor Cyan
    Write-Host $LINE_MID -ForegroundColor Cyan

    # Ligne RAM - construite en une seule string, couleur unique par Write-Host
    $ramStats = " " + $ram.pct + "%  (" + $ram.used + "/" + $ram.total + " GB)"
    $ramContent = "  RAM  " + $bar + (Fit-String $ramStats ($CONTENT_W - 7 - 10))
    Write-Host (Make-BoxLine "    " $ramContent) -ForegroundColor $ramColor

    # Ligne profil actif
    $profileStr = "  Profil actif : " + $ActiveName + " (" + $ActiveMem + ")"
    Write-Host (Make-BoxLine "    " $profileStr) -ForegroundColor White

    Write-Host $LINE_MID -ForegroundColor Cyan
}

# ---- Menu interactif ------------------------------------------------

function Show-InteractiveMenu {

    $config      = Get-ProfileConfig
    $active      = Get-ActiveProfile -Config $config
    $profileKeys = $config.profiles.PSObject.Properties.Name

    $menuItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($key in $profileKeys) {
        $p = $config.profiles.$key
        $menuItems.Add([PSCustomObject]@{
            type        = "profile"
            key         = $key
            label       = $p.displayName
            description = $p.description
            memory      = $p.memory
            color       = $p.color
            isActive    = ($key -eq $active.key)
        })
    }

    $menuItems.Add([PSCustomObject]@{ type="separator"; key=""; label=""; description=""; memory=""; color="DarkGray"; isActive=$false })
    $menuItems.Add([PSCustomObject]@{ type="action"; key="history";  label="Historique"; description=""; memory=""; color="Gray";       isActive=$false })
    $menuItems.Add([PSCustomObject]@{ type="action"; key="rollback"; label="Rollback";   description=""; memory=""; color="DarkYellow"; isActive=$false })
    $menuItems.Add([PSCustomObject]@{ type="action"; key="quit";     label="Quitter";    description=""; memory=""; color="DarkGray";   isActive=$false })

    # [int[]] explicite pour eviter le bug de cast PS sur tableau scalaire
    [int[]]$selectableIdx = @(
        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            if ($menuItems[$i].type -ne "separator") { $i }
        }
    )
    [int]$pos = 0

    do {
        [int]$currentIdx = $selectableIdx[$pos]
        Show-Header -ActiveName $active.name -ActiveMem $active.memory

        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            $item       = $menuItems[$i]
            $isSelected = ($i -eq $currentIdx)

            if ($item.type -eq "separator") {
                Write-Host $LINE_SEP -ForegroundColor DarkGray
                continue
            }

            $cursor = if ($isSelected) { "  > " } else { "    " }

            if ($item.type -eq "profile") {
                $memRaw  = if ($item.memory)   { "(" + $item.memory + ")" } else { "" }
                $mark    = if ($item.isActive) { "[v]" } else { "" }

                $label   = Fit-String $item.label         $LABEL_W
                $desc    = Fit-String $item.description   $DESC_W
                $mem     = Fit-String ($memRaw + $mark)   $MEM_W
                $content = $label + $desc + $mem

                $color = if ($isSelected) { "Yellow" } else { $item.color }
                Write-Host (Make-BoxLine $cursor $content) -ForegroundColor $color
            }
            else {
                $content = Fit-String $item.label $CONTENT_W
                $color   = if ($isSelected) { "Yellow" } else { $item.color }
                Write-Host (Make-BoxLine $cursor $content) -ForegroundColor $color
            }
        }

        Write-Host $LINE_BOT -ForegroundColor Cyan
        Write-Host "    haut/bas Naviguer   Entree Selectionner   Q Quitter" -ForegroundColor DarkGray
        Write-Host ""

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow"   { if ($pos -gt 0)                        { $pos-- } }
            "DownArrow" { if ($pos -lt $selectableIdx.Count - 1) { $pos++ } }
            "Enter"     { return $menuItems[$currentIdx].key }
            "Q"         { return "quit" }
            "Escape"    { return "quit" }
        }

    } while ($true)
}

# ---- Point d'entree -------------------------------------------------

if ($Version) {
    Write-Host "WSL2 Profile Switcher v$($Global:AppVersion)" -ForegroundColor Cyan
    exit
}

if ($Monitor -ne "") {
    switch ($Monitor.ToLower()) {
        "start"  { Start-WslMonitor; exit }
        "stop"   { Stop-WslMonitor;  exit }
        "status" { Get-MonitorStatus; exit }
        default  { Write-Host "Usage : -Monitor start|stop|status" -ForegroundColor Red; exit 1 }
    }
}
if ($Clean) {
    $reportsDir  = Join-Path $PSScriptRoot "data\reports"
    $cooldown    = Join-Path $PSScriptRoot "data\monitor_cooldown.txt"
    $errors      = Join-Path $PSScriptRoot "data\monitor_errors.txt"
    $cleaned     = 0
    if (Test-Path $reportsDir) {
        $all = Get-ChildItem $reportsDir -Filter "report_*.txt" | Sort-Object Name
        if ($all.Count -gt 12) {
            $toDelete = $all | Select-Object -First ($all.Count - 12)
            $toDelete | Remove-Item -Force
            $cleaned += $toDelete.Count
            Write-Host "  Rapports supprimes : $($toDelete.Count)" -ForegroundColor Gray
        } else {
            Write-Host "  Rapports : rien a purger ($($all.Count)/12)" -ForegroundColor DarkGray
        }
    }
    foreach ($tmp in @($cooldown, $errors)) {
        if (Test-Path $tmp) {
            Remove-Item $tmp -Force
            Write-Host "  Supprime : $(Split-Path $tmp -Leaf)" -ForegroundColor Gray
            $cleaned++
        }
    }
    Write-Host ""
    if ($cleaned -eq 0) { Write-Host "  Rien a nettoyer." -ForegroundColor DarkGray }
    else { Write-Host "  Nettoyage termine ($cleaned element(s) supprimes)." -ForegroundColor Green }
    Write-Host ""
    exit
}
if ($Report)  { & (Join-Path $PSScriptRoot "modules\WeeklyReport.ps1"); exit }
if ($Rollback) { Invoke-Rollback; exit }
if ($History)  { Show-SwitchHistory; exit }
if ($Export)   { Export-Profiles; exit }

if ($Import -ne "") {
    try   { Import-Profiles -Path $Import }
    catch { Write-Host "ERREUR : $_" -ForegroundColor Red; exit 1 }
    exit
}

if ($NewProfile -ne "") {
    $parts = $NewProfile -split "\s+"
    if ($parts.Count -lt 3) {
        Write-Host "Usage : -NewProfile 'nomCle XGBRAM NbCPU [description]'" -ForegroundColor Red
        exit 1
    }
    if ($parts[0] -notmatch "^[a-zA-Z][a-zA-Z0-9_-]*$") {
        Write-Host "  ERREUR : La cle de profil doit etre un identifiant alphanumerique (ex: gaming, ml-heavy)." -ForegroundColor Red
        exit 1
    }
    $desc = if ($parts.Count -ge 4) { $parts[3..($parts.Count-1)] -join " " } else { "Profil personnalise" }
    try   { New-CustomProfile -Key $parts[0] -Memory $parts[1] -Processors ([int]$parts[2]) -Description $desc }
    catch { Write-Host "ERREUR : $_" -ForegroundColor Red; exit 1 }
    exit
}

if ($Profil -ne "") {
    try   { Set-WslProfile -Key $Profil.ToLower() -DryRun:$DryRun }
    catch { Write-Host "ERREUR : $_" -ForegroundColor Red; exit 1 }
    exit
}

# Mode par defaut : menu interactif
do {
    $choice = Show-InteractiveMenu

    switch ($choice) {
        "quit" {
            Clear-Host
            exit
        }
        "history" {
            Show-SwitchHistory
            Write-Host "  Appuyez sur Entree pour continuer..." -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "rollback" {
            Invoke-Rollback
            Write-Host "  Appuyez sur Entree pour continuer..." -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        default {
            if ($choice -ne "") {
                try {
                    Set-WslProfile -Key $choice
                    Write-Host "  Appuyez sur Entree pour continuer..." -ForegroundColor DarkGray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
                catch {
                    Write-Host ""
                    Write-Host "  ERREUR : $_" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "  Appuyez sur Entree pour continuer..." -ForegroundColor DarkGray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
        }
    }

} while ($true)








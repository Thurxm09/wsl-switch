#!/usr/bin/env python3
# Fix-WslSwitch-Main.py
# Corrige wsl-switch.ps1 : param block, ErrorActionPreference, Clear-Host, Get-RamInfo
# Usage depuis WSL2 : python3 /mnt/c/Scripts/WSL-Switch/Fix-WslSwitch-Main.py
# Usage depuis Windows : python Fix-WslSwitch-Main.py

import sys, os

base = '/mnt/c/Scripts/WSL-Switch' if sys.platform != 'win32' else r'C:\Scripts\WSL-Switch'
target = os.path.join(base, 'wsl-switch.ps1')

with open(target, 'r', encoding='utf-8') as f:
    src = f.read()

ok = True

# ------------------------------------------------------------------ #
# Fix 1 : ajouter [switch]$DebugMode dans le bloc param              #
# ------------------------------------------------------------------ #
OLD1 = '    [switch]$Version\n)'
NEW1 = '    [switch]$Version,\n    [switch]$DebugMode\n)'
if OLD1 in src:
    src = src.replace(OLD1, NEW1)
    print("  [OK] Fix 1 : [switch]$DebugMode ajoute au bloc param")
else:
    print("  [SKIP] Fix 1 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 2 : ajouter gestion ErrorActionPreference AVANT Bootstrap      #
# ------------------------------------------------------------------ #
OLD2 = '# ---- Bootstrap ------------------------------------------------------\n\n$Global:WSLRoot = $PSScriptRoot'
NEW2 = (
    '# ---- Gestion des erreurs -------------------------------------------\n'
    '# Doit etre defini avant tout pour capturer les erreurs des modules\n'
    '\n'
    'if ($DebugMode) {\n'
    '    $ErrorActionPreference = \'Continue\'\n'
    '    $VerbosePreference     = \'Continue\'\n'
    '    Write-Host "  [DEBUG] Mode debug actif - erreurs affichees" -ForegroundColor Magenta\n'
    '} else {\n'
    '    $ErrorActionPreference = \'Stop\'\n'
    '}\n'
    '\n'
    '# ---- Bootstrap ------------------------------------------------------\n'
    '\n'
    '$Global:WSLRoot = $PSScriptRoot'
)
if OLD2 in src:
    src = src.replace(OLD2, NEW2)
    print("  [OK] Fix 2 : ErrorActionPreference ajoute avant Bootstrap")
else:
    print("  [SKIP] Fix 2 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 3 : Get-RamInfo avec try/catch + ErrorAction Stop              #
# ------------------------------------------------------------------ #
OLD3 = (
    'function Get-RamInfo {\n'
    '    $os    = Get-CimInstance Win32_OperatingSystem\n'
    '    $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)\n'
    '    $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)\n'
    '    $used  = [math]::Round($total - $free, 1)\n'
    '    $pct   = [math]::Round($used / $total * 100, 0)\n'
    '    return [PSCustomObject]@{ total = $total; used = $used; pct = $pct }\n'
    '}'
)
NEW3 = (
    'function Get-RamInfo {\n'
    '    try {\n'
    '        $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop\n'
    '        $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)\n'
    '        $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)\n'
    '        $used  = [math]::Round($total - $free, 1)\n'
    '        $pct   = [math]::Round($used / $total * 100, 0)\n'
    '        return [PSCustomObject]@{ total = $total; used = $used; pct = $pct }\n'
    '    }\n'
    '    catch {\n'
    '        if ($DebugMode) { Write-Host "  [DEBUG] Get-RamInfo : $_" -ForegroundColor DarkYellow }\n'
    '        return [PSCustomObject]@{ total = 0; used = 0; pct = 0 }\n'
    '    }\n'
    '}'
)
if OLD3 in src:
    src = src.replace(OLD3, NEW3)
    print("  [OK] Fix 3 : Get-RamInfo protege avec try/catch")
else:
    print("  [SKIP] Fix 3 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 4 : Show-Header - Clear-Host en premier avant Get-RamInfo      #
# ------------------------------------------------------------------ #
OLD4 = (
    '    $ram      = Get-RamInfo\n'
    '    $bar      = Get-RamBar -Pct $ram.pct\n'
    '    $ramColor = if ($ram.pct -ge 80) { "Red" } elseif ($ram.pct -ge 60) { "Yellow" } else { "Green" }\n'
    '\n'
    '    Clear-Host\n'
    '    Write-Host ""\n'
    '    Write-Host $LINE_TOP -ForegroundColor Cyan'
)
NEW4 = (
    '    Clear-Host\n'
    '    Write-Host ""\n'
    '\n'
    '    $ram      = Get-RamInfo\n'
    '    $bar      = Get-RamBar -Pct $ram.pct\n'
    '    $ramColor = if ($ram.pct -ge 80) { "Red" } elseif ($ram.pct -ge 60) { "Yellow" } else { "Green" }\n'
    '\n'
    '    Write-Host $LINE_TOP -ForegroundColor Cyan'
)
if OLD4 in src:
    src = src.replace(OLD4, NEW4)
    print("  [OK] Fix 4 : Clear-Host deplace en premier dans Show-Header")
else:
    print("  [SKIP] Fix 4 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 5 : Mettre a jour le commentaire USAGE                         #
# ------------------------------------------------------------------ #
OLD5 = '#  .\\.wsl-switch.ps1 -Import path.json  -> importer profils\n#\n# ='
NEW5 = '#  .\\.wsl-switch.ps1 -Import path.json  -> importer profils\n#  .\\.wsl-switch.ps1 -DebugMode         -> mode debug (erreurs visibles)\n#\n# ='

# Le commentaire USAGE utilise des backslashes dans les chemins
OLD5b = '#  .\\wsl-switch.ps1 -Import path.json  -> importer profils\n#\n# ='
NEW5b = '#  .\\wsl-switch.ps1 -Import path.json  -> importer profils\n#  .\\wsl-switch.ps1 -DebugMode         -> mode debug (erreurs visibles)\n#\n# ='

if OLD5 in src:
    src = src.replace(OLD5, NEW5)
    print("  [OK] Fix 5 : commentaire USAGE mis a jour")
elif OLD5b in src:
    src = src.replace(OLD5b, NEW5b)
    print("  [OK] Fix 5 : commentaire USAGE mis a jour")
else:
    print("  [SKIP] Fix 5 : commentaire USAGE introuvable (non bloquant)")

# ------------------------------------------------------------------ #
# Ecriture du fichier corrige                                        #
# ------------------------------------------------------------------ #
with open(target, 'w', encoding='utf-8') as f:
    f.write(src)

print("\n  => wsl-switch.ps1 corrige avec succes.")

#!/usr/bin/env python3
# Fix-ProfileManager.py
# Corrige modules/ProfileManager.ps1 : ecriture sans BOM, ErrorAction Stop
# Usage depuis WSL2 : python3 /mnt/c/Scripts/WSL-Switch/Fix-ProfileManager.py
# Usage depuis Windows : python Fix-ProfileManager.py

import sys, os

base = '/mnt/c/Scripts/WSL-Switch' if sys.platform != 'win32' else r'C:\Scripts\WSL-Switch'
target = os.path.join(base, 'modules', 'ProfileManager.ps1')

with open(target, 'r', encoding='utf-8') as f:
    src = f.read()

# ------------------------------------------------------------------ #
# Fix 1 : Set-Content remplace par WriteAllText sans BOM             #
# Raison : PS5.1 Set-Content -Encoding UTF8 ecrit un BOM (U+FEFF)   #
# WSL2 peut ignorer silencieusement un .wslconfig avec BOM           #
# ------------------------------------------------------------------ #
OLD1 = '    Set-Content -Path (Get-WslConfigPath) -Value $content -Encoding UTF8'
NEW1 = '    [System.IO.File]::WriteAllText((Get-WslConfigPath), $content, [System.Text.UTF8Encoding]::new($false))'
if OLD1 in src:
    src = src.replace(OLD1, NEW1)
    print("  [OK] Fix 1 : Set-Content remplace par WriteAllText (sans BOM)")
else:
    print("  [SKIP] Fix 1 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 2 : Get-Content dans Get-ActiveProfile avec -ErrorAction Stop  #
# ------------------------------------------------------------------ #
OLD2 = '    $lines = Get-Content $wslConfig -Encoding UTF8'
NEW2 = '    $lines = Get-Content $wslConfig -Encoding UTF8 -ErrorAction Stop'
if OLD2 in src:
    src = src.replace(OLD2, NEW2)
    print("  [OK] Fix 2 : Get-Content dans Get-ActiveProfile protege")
else:
    print("  [SKIP] Fix 2 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Fix 3 : Get-Content dans Get-ProfileConfig avec -ErrorAction Stop  #
# ------------------------------------------------------------------ #
OLD3 = '    $raw = Get-Content $path -Raw -Encoding UTF8\n    if ([string]::IsNullOrWhiteSpace($raw))'
NEW3 = '    $raw = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop\n    if ([string]::IsNullOrWhiteSpace($raw))'
if OLD3 in src:
    src = src.replace(OLD3, NEW3)
    print("  [OK] Fix 3 : Get-Content dans Get-ProfileConfig protege")
else:
    print("  [SKIP] Fix 3 : deja applique ou pattern introuvable")

# ------------------------------------------------------------------ #
# Ecriture du fichier corrige                                        #
# ------------------------------------------------------------------ #
with open(target, 'w', encoding='utf-8') as f:
    f.write(src)

print("\n  => ProfileManager.ps1 corrige avec succes.")

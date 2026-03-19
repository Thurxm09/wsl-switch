# ============================================================
#  Write-GitFiles.ps1
#  Cree uniquement les fichiers GitHub manquants.
#  Aucun fichier local existant n'est touche ou supprime.
#  Usage : .\Write-GitFiles.ps1
# ============================================================

$root = "C:\Scripts\WSL-Switch"

Write-Host ""
Write-Host "  WSL-Switch - Preparation GitHub" -ForegroundColor Cyan
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# ============================================================
#  1. .gitignore
# ============================================================
$gitignore = @'
# Fichiers runtime - utiles en local, exclus du repo
data/history.json
data/wslconfig.backup
data/monitor_cooldown.txt
data/monitor_errors.txt
data/reports/

# Bootstraps de deploiement - utiles en local, exclus du repo
Write-Phase2.ps1
Write-Phase3.ps1
Write-WslSwitch.ps1

# Fichiers systeme
Thumbs.db
Desktop.ini
.DS_Store

# VSCode
.vscode/*.log
'@

Set-Content "$root\.gitignore" -Value $gitignore -Encoding ASCII
Write-Host "  [+] .gitignore" -ForegroundColor Green

# ============================================================
#  2. LICENSE (MIT)
# ============================================================
$year = (Get-Date).Year
$license = "MIT License`r`n`r`nCopyright (c) $year Thuram`r`n`r`n" +
"Permission is hereby granted, free of charge, to any person obtaining a copy " +
"of this software and associated documentation files (the ""Software""), to deal " +
"in the Software without restriction, including without limitation the rights " +
"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell " +
"copies of the Software, and to permit persons to whom the Software is " +
"furnished to do so, subject to the following conditions:`r`n`r`n" +
"The above copyright notice and this permission notice shall be included in all " +
"copies or substantial portions of the Software.`r`n`r`n" +
"THE SOFTWARE IS PROVIDED ""AS IS"", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR " +
"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, " +
"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE " +
"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER " +
"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, " +
"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."

Set-Content "$root\LICENSE" -Value $license -Encoding ASCII
Write-Host "  [+] LICENSE (MIT)" -ForegroundColor Green

# ============================================================
#  3. CHANGELOG.md
# ============================================================
$changelog = @'
# WSL2 Profile Switcher - Changelog

## v2.0 - 2026-03-18

### Architecture
- Refactoring complet : script monolithique -> structure modulaire 5 fichiers
- Profils externalises dans data/profiles.json (plus de code a modifier)
- Separation claire : logique metier / interface / monitoring / reporting

### Phase 1 - Foundation
- Menu interactif a navigation clavier (fleches + Entree)
- Backup automatique de .wslconfig avant chaque switch
- Rollback instantane via wsl-switch -Rollback
- Validation post-ecriture avec rollback automatique si .wslconfig invalide
- Historique complet des operations dans data/history.json
- Mode simulation -DryRun sans ecriture systeme
- Creation de profils personnalises via CLI
- Import / export des profils en JSON

### Phase 2 - Monitoring RAM
- Surveillance RAM WSL2 via tache planifiee Windows (sans terminal ouvert)
- Detection du process vmmem comme proxy de la consommation WSL2
- Alertes Toast Windows natives via API Windows Runtime
- Systeme de cooldown (30 min entre deux alertes)
- Commandes : -Monitor start|stop|status

### Phase 3 - Reporting
- Rapport hebdomadaire automatique chaque lundi a 09h00
- Generation manuelle via wsl-switch -Report
- Contenu : repartition par profil, profil dominant, heure de pointe, derniers switchs
- Sauvegarde dans data/reports/report_YYYY-MM-DD.txt
- Rotation automatique : 12 rapports maximum conserves

### Ameliorations transversales
- Alias global PowerShell wsl-switch (disponible partout sans cd)
- Validation du JSON profiles.json au demarrage avec messages d'erreur actionnables
- Commande wsl-switch -Clean pour purger les fichiers temporaires

---

## v1.0 - Initial

- Switch entre profils WEB (2GB) et DATA SCIENCE (6GB)
- Affichage du profil actif et de la RAM Windows
- Aide utilisateur basique
'@

Set-Content "$root\CHANGELOG.md" -Value $changelog -Encoding ASCII
Write-Host "  [+] CHANGELOG.md" -ForegroundColor Green

# ============================================================
#  4. README.md
# ============================================================
$readme = @'
# WSL2 Profile Switcher

> Gestionnaire de profils WSL2 avec menu interactif, surveillance RAM et reporting hebdomadaire.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Pourquoi ce projet ?

Sur une machine de 16 Go, laisser WSL2 consommer 6 Go en permanence pour un travail
de navigation web n'a aucun sens. Ce projet permet de basculer instantanement entre
des profils memoire adaptes a chaque usage, avec une interface claire et sans jamais
editer .wslconfig a la main.

---

## Fonctionnalites

- **Menu interactif** navigation clavier - aucun flag a memoriser
- **Profils JSON** extensibles sans toucher au code
- **Backup automatique** avant chaque switch + rollback instantane
- **Surveillance RAM** en arriere-plan via tache planifiee Windows
- **Alertes Toast** natives quand WSL2 depasse le seuil configure
- **Rapport hebdomadaire** automatique chaque lundi
- **Historique** complet de toutes les operations
- **Mode dry-run** pour simuler sans appliquer
- **Alias global** wsl-switch disponible partout dans le terminal

---

## Installation

```powershell
# 1. Cloner le depot
git clone https://github.com/<votre-username>/wsl-switch.git C:\Scripts\WSL-Switch

# 2. Autoriser l'execution des scripts locaux
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 3. Debloquer les fichiers
Get-ChildItem C:\Scripts\WSL-Switch -Recurse -Filter *.ps1 | Unblock-File

# 4. Ajouter l'alias global (optionnel mais recommande)
Add-Content -Path $PROFILE -Value "`nfunction wsl-switch { & 'C:\Scripts\WSL-Switch\wsl-switch.ps1' @args }" -Encoding ASCII
. $PROFILE
```

---

## Profils par defaut

| Cle    | RAM  | CPU | Usage typique              |
|--------|------|-----|----------------------------|
| base   | 1 GB | 2   | Navigation, taches legeres |
| web    | 2 GB | 3   | VS Code + Brave            |
| data   | 6 GB | 5   | Jupyter + Pandas + ML      |

---

## Usage

```powershell
wsl-switch                                      # Menu interactif
wsl-switch web                                  # Switch direct
wsl-switch data -DryRun                         # Simulation sans ecriture
wsl-switch -Rollback                            # Restaurer le backup
wsl-switch -History                             # Voir l historique
wsl-switch -Monitor start                       # Lancer la surveillance RAM
wsl-switch -Monitor status                      # Etat du monitoring
wsl-switch -Report                              # Generer un rapport maintenant
wsl-switch -Clean                               # Purger les fichiers temporaires
wsl-switch -NewProfile "perf 10GB 5 Perf"      # Profil personnalise
```

---

## Architecture

```
WSL-Switch/
|-- wsl-switch.ps1              <- Point d entree unique
|-- modules/
|   |-- ProfileManager.ps1      <- Logique profils (apply, backup, rollback)
|   |-- Logger.ps1              <- Historique JSON + rapport hebdo
|   |-- Monitor.ps1             <- Controle de la tache planifiee
|   |-- MonitorTask.ps1         <- Script execute par le scheduler
|   `-- WeeklyReport.ps1        <- Generation des rapports
`-- data/
    |-- profiles.json           <- Definition des profils (source of truth)
    |-- history.json            <- Genere automatiquement (hors repo)
    `-- reports/                <- Rapports hebdomadaires (hors repo)
```

**Principe cle** : wsl-switch.ps1 est le seul point d entree.
Les modules ne se connaissent pas entre eux.

---

## Ajouter un profil personnalise

```powershell
wsl-switch -NewProfile "gaming 12GB 6 Mode gaming"
```

Le profil apparait immediatement dans le menu interactif.

---

## Licence

MIT - voir [LICENSE](LICENSE)
'@

Set-Content "$root\README.md" -Value $readme -Encoding ASCII
Write-Host "  [+] README.md" -ForegroundColor Green

# ============================================================
#  Bilan
# ============================================================
Write-Host ""
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host "  Fichiers crees. Aucun fichier local supprime." -ForegroundColor Green
Write-Host ""
Write-Host "  Prochaines etapes :" -ForegroundColor Gray
Write-Host ""
Write-Host "  cd C:\Scripts\WSL-Switch" -ForegroundColor Gray
Write-Host "  git init" -ForegroundColor Gray
Write-Host "  git add ." -ForegroundColor Gray
Write-Host "  git commit -m 'Initial commit - WSL-Switch v2.0'" -ForegroundColor Gray
Write-Host "  git remote add origin https://github.com/<username>/wsl-switch.git" -ForegroundColor Gray
Write-Host "  git push -u origin main" -ForegroundColor Gray
Write-Host ""

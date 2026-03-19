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

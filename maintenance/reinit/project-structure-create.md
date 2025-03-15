# Script PowerShell pour créer la structure du projet

Maintenant, voici la version PowerShell du script create-project-structure.sh :

```powershell
<#
.SYNOPSIS
    Script pour générer la structure complète du projet MLENV sur Windows
.DESCRIPTION
    Ce script crée tous les répertoires et fichiers nécessaires pour le projet MLENV
.NOTES
    Version:        1.0
    Author:         MLENV Project
    Creation Date:  2025-03-15
#>

# Fonction pour afficher les messages avec horodatage
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host "[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Write-Success {
    param(
        [string]$Message
    )
    Write-Log -Message $Message -Color "Green"
}

# Créer le répertoire racine si nécessaire
if (-not (Test-Path -Path "mlenv")) {
    Write-Log "Création du répertoire mlenv..."
    New-Item -Path "mlenv" -ItemType Directory | Out-Null
}

Set-Location -Path "mlenv"

# Création des répertoires principaux
Write-Log "Création des répertoires principaux..."
$folders = @(
    "proxmox/configuration",
    "storage",
    "ansible/inventory/group_vars",
    "ansible/playbooks",
    "ansible/roles",
    "scripts/recovery",
    "config/jupyter",
    "config/systemd",
    "config/python",
    "doc"
)

foreach ($folder in $folders) {
    if (-not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

# Création des fichiers de configuration VFIO et KVM
Write-Log "Création des fichiers de configuration VFIO et KVM..."
@"
# Configuration VFIO pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/vfio.conf

# Liste des IDs des GPUs NVIDIA à passer en passthrough
# Format: vendorID:deviceID
options vfio-pci ids=10de:XXXX
"@ | Set-Content -Path "proxmox/configuration/vfio.conf" -Encoding UTF8

@"
# Configuration KVM pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/kvm.conf

# Ignorer les MSRs pour éviter les erreurs avec les cartes NVIDIA
options kvm ignore_msrs=1 report_ignored_msrs=0
"@ | Set-Content -Path "proxmox/configuration/kvm.conf" -Encoding UTF8

@"
# Configuration pour blacklister les pilotes NVIDIA natifs sur l'hôte
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/blacklist-nvidia.conf

# Blacklist tous les pilotes NVIDIA pour permettre le passthrough
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
"@ | Set-Content -Path "proxmox/configuration/blacklist-nvidia.conf" -Encoding UTF8

# Création du script de restauration
Write-Log "Création du script de restauration..."
@"
#!/bin/bash
# Script de secours pour restaurer la configuration de démarrage

# Remonter le système de fichiers en lecture-écriture
mount -o remount,rw /

# Désactiver les fichiers de configuration problématiques
if [ -f /etc/modprobe.d/vfio.conf ]; then
    mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.disabled
fi

if [ -f /etc/modprobe.d/blacklist-nvidia.conf ]; then
    mv /etc/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf.disabled
fi

# Restaurer GRUB sans IOMMU
if [ -f /etc/default/grub ]; then
    sed -i 's/intel_iommu=on//g' /etc/default/grub
    sed -i 's/amd_iommu=on//g' /etc/default/grub
    sed -i 's/iommu=pt//g' /etc/default/grub
    update-grub
fi

# Mettre à jour l'initramfs
update-initramfs -u -k all

echo "Configuration restaurée. Redémarrez avec 'reboot'"
"@ | Set-Content -Path "scripts/recovery/restore-boot.sh" -Encoding UTF8

# Création des fichiers de configuration Python
Write-Log "Création des fichiers de configuration Python..."
@"
# Packages Python pour l'environnement de backtesting
numpy
pandas
scipy
matplotlib
seaborn
scikit-learn
statsmodels
pytables
jupyterlab
ipykernel
ipywidgets
pyfolio
backtrader
vectorbt
yfinance
alpha_vantage
ta
ccxt
dash
plotly
psycopg2-binary
SQLAlchemy
tensorflow
torch
torchvision
torchaudio
"@ | Set-Content -Path "config/python/requirements-backtesting.txt" -Encoding UTF8

@"
# Packages Python pour l'environnement de machine learning
numpy
pandas
scipy
matplotlib
seaborn
scikit-learn
statsmodels
pytables
jupyterlab
ipykernel
ipywidgets
tensorflow
tensorflow-gpu
torch
torchvision
torchaudio
transformers
huggingface-hub
xgboost
lightgbm
catboost
optuna
hyperopt
ray[tune]
yfinance
alpha_vantage
ta
ccxt
dash
plotly
psycopg2-binary
SQLAlchemy
gym
stable-baselines3
gpflow
bayesian-optimization
"@ | Set-Content -Path "config/python/requirements-ml.txt" -Encoding UTF8

# Création des fichiers de service systemd
Write-Log "Création des fichiers de service systemd..."
@"
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
User=%USER%
ExecStart=/home/%USER%/venv/bin/jupyter lab --config=/etc/jupyter/jupyter_notebook_config.py
WorkingDirectory=/home/%USER%
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"@ | Set-Content -Path "config/systemd/jupyter.service" -Encoding UTF8

# Création du fichier de configuration Jupyter
Write-Log "Création du fichier de configuration Jupyter..."
@"
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Générer un mot de passe sécurisé avec: 
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
c.NotebookApp.password = ''  # Remplacer par le hash généré
"@ | Set-Content -Path "config/jupyter/jupyter_notebook_config.py" -Encoding UTF8

# Création des scripts de base
Write-Log "Création des scripts utilitaires..."
@"
#!/bin/bash
# Script de sauvegarde pour PredatorX
# À exécuter quotidiennement via cron

DATE=\$(date +%Y-%m-%d)
BACKUP_DIR="/mnt/vmstorage/backups"
LOG_FILE="/var/log/pve-backup/backup-\${DATE}.log"

mkdir -p /var/log/pve-backup
echo "Démarrage des sauvegardes: \$(date)" | tee -a "\$LOG_FILE"

# Sauvegarde des VMs
for VM_ID in \$(qm list | tail -n+2 | awk '{print \$1}')
do
    echo "Sauvegarde de la VM \$VM_ID..." | tee -a "\$LOG_FILE"
    vzdump \$VM_ID --compress zstd --mode snapshot --storage backup | tee -a "\$LOG_FILE"
done

# Sauvegarde des conteneurs
for CT_ID in \$(pct list | tail -n+2 | awk '{print \$1}')
do
    echo "Sauvegarde du conteneur \$CT_ID..." | tee -a "\$LOG_FILE"
    vzdump \$CT_ID --compress zstd --mode snapshot --storage backup | tee -a "\$LOG_FILE"
done

# Conservation des 7 derniers jours de logs uniquement
find /var/log/pve-backup -name "backup-*.log" -mtime +7 -delete

echo "Sauvegardes terminées: \$(date)" | tee -a "\$LOG_FILE"
"@ | Set-Content -Path "scripts/backup.sh" -Encoding UTF8

@"
#!/bin/bash
# Script de maintenance pour PredatorX
# À exécuter périodiquement via cron

# Nettoyage des journaux
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.[0-9]" -delete
journalctl --vacuum-time=3d

# Nettoyage des paquets
apt clean
apt autoremove -y

# Vérification de l'espace disque
DISK_USAGE=\$(df -h / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 85 ]; then
    echo "ALERTE: L'espace disque sur / est à \$DISK_USAGE%" | mail -s "Alerte espace disque sur PredatorX" root
fi

# Mise à jour de l'hôte
apt update && apt list --upgradable
"@ | Set-Content -Path "scripts/maintenance.sh" -Encoding UTF8

# Création du README.md principal
Write-Log "Création du README principal..."
@"
# MLENV - Environnement automatisé pour Backtesting et Machine Learning

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

MLENV est un projet d'Infrastructure as Code (IaC) conçu pour automatiser le déploiement d'un environnement complet de backtesting et machine learning pour le trading algorithmique sur un ancien système de minage de cryptomonnaies.

## Vue d'ensemble

Ce projet transforme un ancien système de minage de cryptomonnaies en une plateforme puissante pour:
- Développer et tester des stratégies de trading algorithmique (backtesting)
- Appliquer des techniques de machine learning aux données financières
- Optimiser les performances grâce au passthrough GPU de multiples cartes NVIDIA
- Centraliser le stockage et l'analyse des données financières

## Architecture
┌─────────────────────────────────────┐
│ Proxmox VE (Système hôte)           │
│                                     │
│ ┌─────────────┐    ┌─────────────┐  │
│ │ VM          │    │ VM          │  │
│ │ Backtesting │    │ Machine     │  │
│ │ (1-2 GPUs)  │    │ Learning    │  │
│ │             │    │ (6-7 GPUs)  │  │
│ └─────────────┘    └─────────────┘  │
│                                     │
│ ┌─────────────┐    ┌─────────────┐  │
│ │ Conteneur   │    │ Conteneur   │  │
│ │ PostgreSQL  │    │ Sauvegardes │  │
│ └─────────────┘    └─────────────┘  │
│                                     │
└─────────────────────────────────────┘

## Guide rapide

1. **Installation de Proxmox VE**
   - Installer Proxmox VE 8.x depuis l'ISO
   
2. **Configuration de Proxmox avec Ansible**
   ```bash
   # Installer Ansible
   apt install -y git ansible
   
   # Cloner ce dépôt
   git clone https://github.com/votre-username/mlenv.git
   cd mlenv/ansible
   
   # Configurer l'environnement
   cp inventory/hosts.example.yml inventory/hosts.yml
   nano inventory/hosts.yml  # Ajuster les variables
   
   # Exécuter le playbook principal
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml
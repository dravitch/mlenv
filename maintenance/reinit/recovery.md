# Document reset-environment.md

Je vais préparer un guide complet pour réinitialiser l'environnement MLENV. Commençons par le document reset-environment.md :

```markdown
# Procédure de réinitialisation de l'environnement MLENV

Ce document décrit la procédure complète pour réinitialiser l'environnement MLENV, tant au niveau du développement Git local que de l'infrastructure Proxmox.

## Table des matières
1. [Réinitialisation de l'environnement Git local](#1-réinitialisation-de-lenvironnement-git-local)
2. [Recréation de la structure du projet](#2-recréation-de-la-structure-du-projet)
3. [Réinitialisation de l'infrastructure Proxmox](#3-réinitialisation-de-linfrastructure-proxmox)
4. [Reconfiguration de Proxmox](#4-reconfiguration-de-proxmox)
5. [Vérification de l'environnement](#5-vérification-de-lenvironnement)

## 1. Réinitialisation de l'environnement Git local

### Windows 11
```powershell
# Accéder au répertoire du projet
cd C:\chemin\vers\mlenv

# Supprimer les fichiers de suivi Git
Remove-Item -Path .git -Recurse -Force

# Supprimer tous les fichiers du projet (ATTENTION: cette opération est irréversible)
Remove-Item -Path * -Recurse -Force

# Réinitialiser Git
git init
git config user.name "Votre Nom"
git config user.email "votre.email@exemple.com"

# Créer le fichier .gitignore
@"
# Fichiers système
.DS_Store
Thumbs.db

# Fichiers d'environnement
.env
.venv
env/
venv/
ENV/

# Fichiers de configuration personnels
config.local.yml

# Fichiers de compilation Python
*.py[cod]
*$py.class
__pycache__/

# Fichiers de logs
*.log
logs/

# Fichiers temporaires
tmp/
temp/
"@ | Out-File -FilePath .gitignore -Encoding utf8
```

### Linux
```bash
# Accéder au répertoire du projet
cd /chemin/vers/mlenv

# Supprimer les fichiers de suivi Git
rm -rf .git

# Supprimer tous les fichiers du projet (ATTENTION: cette opération est irréversible)
rm -rf *

# Réinitialiser Git
git init
git config user.name "Votre Nom"
git config user.email "votre.email@exemple.com"

# Créer le fichier .gitignore
cat > .gitignore << 'EOF'
# Fichiers système
.DS_Store
Thumbs.db

# Fichiers d'environnement
.env
.venv
env/
venv/
ENV/

# Fichiers de configuration personnels
config.local.yml

# Fichiers de compilation Python
*.py[cod]
*$py.class
__pycache__/

# Fichiers de logs
*.log
logs/

# Fichiers temporaires
tmp/
temp/
EOF
```

## 2. Recréation de la structure du projet

### Windows 11
```powershell
# Exécuter le script PowerShell pour recréer la structure
.\Create-ProjectStructure.ps1
```

### Linux
```bash
# Exécuter le script Bash pour recréer la structure
bash create-project-structure.sh
```

## 3. Réinitialisation de l'infrastructure Proxmox

Si vous avez besoin de réinitialiser complètement votre serveur Proxmox :

### Sauvegarde préalable (important)
```bash
# Sur le serveur Proxmox, sauvegarder la configuration
mkdir -p /root/proxmox-backup
cp -r /etc/pve /root/proxmox-backup/
qm list > /root/proxmox-backup/vm-list.txt
pct list > /root/proxmox-backup/ct-list.txt

# Sauvegarder les VMs importantes
for VM_ID in 100 101; do
    vzdump $VM_ID --compress zstd --mode snapshot --storage local
done
```

### Réinstallation de Proxmox
1. Télécharger l'ISO Proxmox VE 8.x
2. Créer une clé USB bootable avec l'ISO
3. Démarrer le serveur depuis la clé USB
4. Suivre l'assistant d'installation :
   - Choisir le disque d'installation : SSD principal
   - Définir le nom d'hôte : predatorx (ou votre nom d'hôte)
   - Configurer les paramètres réseau
   - Définir un mot de passe root sécurisé

## 4. Reconfiguration de Proxmox

Après la réinstallation, vous devez reconfigurer l'environnement :

```bash
# Accéder au serveur Proxmox via SSH
ssh root@IP-DU-SERVEUR

# Installer Git et Ansible
apt update && apt install -y git ansible

# Cloner le dépôt MLENV
git clone https://github.com/votre-username/mlenv.git
cd mlenv

# Configurer l'environnement avec Ansible
cd ansible
cp inventory/hosts.example.yml inventory/hosts.yml
nano inventory/hosts.yml  # Ajuster selon votre environnement

# Exécuter le playbook principal
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## 5. Vérification de l'environnement

### Vérifier Proxmox
1. Accéder à l'interface web Proxmox : https://IP-DU-SERVEUR:8006
2. Vérifier que les VMs et conteneurs sont bien créés
3. Vérifier la configuration du stockage

### Vérifier le passthrough GPU
```bash
# Sur le serveur Proxmox
lspci -nnk | grep -i nvidia -A3

# Dans les VMs (après installation)
nvidia-smi
```

### Vérifier les services
1. Accéder à Jupyter dans les VMs : http://IP-VM:8888
2. Vérifier la base de données : `psql -h IP-CONTENEUR-DB -U postgres`

Si certaines vérifications échouent, consultez les logs correspondants et corrigez les problèmes spécifiques.
```

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

```
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
```

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
   ```

3. **Accès aux services**
   - Interface Proxmox: https://IP-SERVER:8006
   - Jupyter (VM Backtesting): http://IP-VM-BACKTESTING:8888
   - Jupyter (VM ML): http://IP-VM-ML:8888
   - PostgreSQL: IP-CONTAINER-DB:5432

## Documentation détaillée

Consultez le dossier `doc/` pour la documentation complète:
- [Installation](doc/installation.md)
- [Configuration](doc/configuration.md)
- [Utilisation](doc/usage.md)
- [Maintenance](doc/maintenance.md)
- [Réinitialisation](doc/reset-environment.md)

## Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.
"@ | Set-Content -Path "README.md" -Encoding UTF8

# Création des playbooks Ansible de base
Write-Log "Création des playbooks Ansible de base..."

# hosts.example.yml
@"
---
all:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    proxmox_hostname: '{{ server_hostname }}'
    storage_dir: /mnt/vmstorage
  children:
    proxmox:
      hosts:
        proxmox-server:
          ansible_host: "{{ server_ip }}"
    vms:
      hosts:
        backtesting-vm:
          ansible_host: "{{ backtesting_ip }}"
        ml-vm:
          ansible_host: "{{ ml_ip }}"
    containers:
      hosts:
        db-container:
          ansible_host: "{{ db_container_ip }}"
        backup-container:
          ansible_host: "{{ backup_container_ip }}"

# Variables à remplacer:
# server_hostname: Nom d'hôte du serveur Proxmox (ex: predatorx)
# server_ip: Adresse IP du serveur Proxmox
# backtesting_ip: Adresse IP de la VM de backtesting
# ml_ip: Adresse IP de la VM de machine learning
# db_container_ip: Adresse IP du conteneur de base de données
# backup_container_ip: Adresse IP du conteneur de sauvegarde
"@ | Set-Content -Path "ansible/inventory/hosts.example.yml" -Encoding UTF8

# site.yml
@"
---
# Playbook principal pour la configuration complète
- name: Configure Proxmox Server
  hosts: proxmox
  become: yes
  tasks:
    - name: Include post-installation tasks
      include_tasks: proxmox-setup.yml

- name: Create and Configure VMs
  hosts: proxmox
  become: yes
  tasks:
    - name: Include VM configuration tasks
      include_tasks: vm-setup.yml

- name: Create and Configure Containers
  hosts: proxmox
  become: yes
  tasks:
    - name: Include container configuration tasks
      include_tasks: container-setup.yml

- name: Configure Backtesting VM
  hosts: backtesting-vm
  become: yes
  tasks:
    - name: Include backtesting VM configuration tasks
      include_tasks: backtesting-vm-setup.yml

- name: Configure Machine Learning VM
  hosts: ml-vm
  become: yes
  tasks:
    - name: Include ML VM configuration tasks
      include_tasks: ml-vm-setup.yml
"@ | Set-Content -Path "ansible/playbooks/site.yml" -Encoding UTF8

# proxmox-setup.yml
@"
---
# Tâches pour la configuration de base de Proxmox
- name: Update package cache
  apt:
    update_cache: yes

- name: Install required packages
  apt:
    name:
      - zfsutils-linux
      - htop
      - iotop
      - git
      - curl
      - chrony
    state: present

- name: Configure repositories
  block:
    - name: Add non-subscription repository
      copy:
        dest: /etc/apt/sources.list.d/pve-no-subscription.list
        content: |
          deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
          deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
        mode: '0644'

    - name: Disable enterprise repository
      replace:
        path: /etc/apt/sources.list.d/pve-enterprise.list
        regexp: '^deb'
        replace: '#deb'
      ignore_errors: yes

    - name: Update package cache after repo changes
      apt:
        update_cache: yes

- name: Configure IOMMU
  block:
    - name: Detect CPU vendor
      shell: lscpu | grep "Vendor ID" | awk '{print $3}'
      register: cpu_vendor
      changed_when: false

    - name: Set IOMMU flag based on CPU vendor
      set_fact:
        iommu_flag: "{% if 'AMD' in cpu_vendor.stdout %}amd_iommu=on{% else %}intel_iommu=on{% endif %}"

    - name: Configure GRUB for IOMMU
      replace:
        path: /etc/default/grub
        regexp: 'GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"'
        replace: 'GRUB_CMDLINE_LINUX_DEFAULT="\1 {{ iommu_flag }} iommu=pt"'
      register: grub_updated

    - name: Update GRUB if configuration changed
      shell: update-grub
      when: grub_updated.changed

- name: Configure VFIO modules
  blockinfile:
    path: /etc/modules
    block: |
      vfio
      vfio_iommu_type1
      vfio_pci
    marker: "# {mark} ANSIBLE MANAGED BLOCK - VFIO modules"
    create: yes

- name: Setup backup directory
  file:
    path: "{{ storage_dir }}/backups"
    state: directory
    mode: '0755'
    recurse: yes

- name: Install backup script
  copy:
    src: ../../scripts/backup.sh
    dest: /usr/local/bin/pve-backup.sh
    mode: '0755'

- name: Setup backup cron job
  cron:
    name: "Proxmox backup"
    minute: "0"
    hour: "1"
    job: "/usr/local/bin/pve-backup.sh"
"@ | Set-Content -Path "ansible/playbooks/proxmox-setup.yml" -Encoding UTF8

# variables.yml
@"
---
# Variables globales pour le projet MLENV
# Variables serveur
server_hostname: predatorx
server_ip: 192.168.1.100

# Variables stockage
storage_dir: /mnt/vmstorage
storage_type: directory  # Options: zfs, lvm, directory

# Variables VMs
vm_ids:
  backtesting: 100
  ml: 101
  web: 102

backtesting_ip: 192.168.1.101
backtesting_cores: 2
backtesting_memory: 8192
backtesting_disk: 40

ml_ip: 192.168.1.102
ml_cores: 2
ml_memory: 8192
ml_disk: 40

# Variables conteneurs
container_ids:
  db: 200
  backup: 201

db_container_ip: 192.168.1.201
backup_container_ip: 192.168.1.202

# Variables GPU
gpu_passthrough: true
gpu_devices:
  - id: "01:00.0"
    vm: backtesting
    options: "pcie=1,x-vga=on"
  - id: "02:00.0"
    vm: backtesting
    options: "pcie=1"
  - id: "03:00.0"
    vm: ml
    options: "pcie=1,x-vga=on"
  - id: "04:00.0"
    vm: ml
    options: "pcie=1"
  - id: "06:00.0"
    vm: ml
    options: "pcie=1"
  - id: "07:00.0"
    vm: ml
    options: "pcie=1"
  - id: "08:00.0"
    vm: ml
    options: "pcie=1"
  - id: "09:00.0"
    vm: ml
    options: "pcie=1"

# Variables utilisateurs
users:
  backtesting:
    name: backtester
    password: "backtester"
  ml:
    name: aitrader
    password: "aitrader"

# Variables Jupyter
jupyter_port: 8888
"@ | Set-Content -Path "ansible/inventory/group_vars/all.yml" -Encoding UTF8

# Création du fichier LICENSE
@"
MIT License

Copyright (c) 2025 MLENV Project

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@ | Set-Content -Path "LICENSE" -Encoding UTF8

# Création du script environnement personnalisé (adaptation à l'environnement local)
@"
<#
.SYNOPSIS
    Script pour personnaliser l'environnement MLENV avec vos variables locales
.DESCRIPTION
    Ce script remplace les variables génériques dans le projet MLENV par vos valeurs locales
.NOTES
    Version:        1.0
    Author:         MLENV Project
    Creation Date:  2025-03-15
#>

# Variables à personnaliser
`$server_hostname = "predatorx"
`$server_ip = "192.168.1.100"
`$backtesting_ip = "192.168.1.101"
`$ml_ip = "192.168.1.102"
`$db_container_ip = "192.168.1.201"
`$backup_container_ip = "192.168.1.202"

# Fonction pour remplacer les variables dans un fichier
function Replace-Variables {
    param(
        [string]`$FilePath
    )
    
    if (Test-Path -Path `$FilePath) {
        `$content = Get-Content -Path `$FilePath -Raw
        
        # Remplacer les variables
        `$content = `$content -replace '{{ server_hostname }}', `$server_hostname
        `$content = `$content -replace '{{ server_ip }}', `$server_ip
        `$content = `$content -replace '{{ backtesting_ip }}', `$backtesting_ip
        `$content = `$content -replace '{{ ml_ip }}', `$ml_ip
        `$content = `$content -replace '{{ db_container_ip }}', `$db_container_ip
        `$content = `$content -replace '{{ backup_container_ip }}', `$backup_container_ip
        
        # Enregistrer les modifications
        Set-Content -Path `$FilePath -Value `$content
        Write-Host "Variables remplacées dans `$FilePath" -ForegroundColor Green
    }
    else {
        Write-Host "Le fichier `$FilePath n'existe pas" -ForegroundColor Red
    }
}

# Fichiers à personnaliser
`$filesToPersonalize = @(
    "ansible/inventory/hosts.yml",
    "ansible/inventory/group_vars/all.yml",
    "README.md"
)

# Créer hosts.yml à partir de l'exemple
if (-not (Test-Path -Path "ansible/inventory/hosts.yml") -and (Test-Path -Path "ansible/inventory/hosts.example.yml")) {
    Copy-Item -Path "ansible/inventory/hosts.example.yml" -Destination "ansible/inventory/hosts.yml"
    Write-Host "Fichier hosts.yml créé à partir de l'exemple" -ForegroundColor Green
}

# Remplacer les variables dans chaque fichier
foreach (`$file in `$filesToPersonalize) {
    Replace-Variables -FilePath `$file
}

Write-Host "Personnalisation de l'environnement terminée!" -ForegroundColor Green
Write-Host "Vos fichiers ont été mis à jour avec vos variables locales." -ForegroundColor Green
"@ | Set-Content -Path "Personalize-Environment.ps1" -Encoding UTF8

# Message final
Write-Success "Structure du projet MLENV créée avec succès!"
Write-Host "Structure créée dans le dossier: $(Get-Location)" -ForegroundColor Cyan
Write-Host "Pour personnaliser l'environnement avec vos variables locales, exécutez:" -ForegroundColor Cyan
Write-Host "  .\Personalize-Environment.ps1" -ForegroundColor Yellow
Write-Host "Assurez-vous d'ajuster les variables dans ce script avant de l'exécuter." -ForegroundColor Cyan
```

# Fichier de configuration Proxmox avec Ansible

Voici maintenant le fichier ansible/playbooks/vm-setup.yml pour créer et configurer les VMs dans Proxmox :

```yaml
---
# Playbook pour la création et configuration des VMs

- name: Create VM storage directory if not exists
  file:
    path: "{{ storage_dir }}/images"
    state: directory
    mode: '0755'

- name: Download Ubuntu ISO if needed
  get_url:
    url: https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso
    dest: "{{ storage_dir }}/iso/ubuntu-22.04.4-live-server-amd64.iso"
    mode: '0644'
  register: iso_download
  ignore_errors: yes
  
- name: Create ISO directory if not exists
  file:
    path: "{{ storage_dir }}/iso"
    state: directory
    mode: '0755'
  when: iso_download is failed

- name: Download Ubuntu ISO again if needed
  get_url:
    url: https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso
    dest: "{{ storage_dir }}/iso/ubuntu-22.04.4-live-server-amd64.iso"
    mode: '0644'
  when: iso_download is failed

- name: Add VM storage to Proxmox
  shell: pvesm add dir vm-storage --path {{ storage_dir }}/images --content images,rootdir
  register: add_storage
  failed_when: add_storage.rc != 0 and 'already defined' not in add_storage.stderr
  changed_when: add_storage.rc == 0

- name: Add ISO storage to Proxmox
  shell: pvesm add dir iso --path {{ storage_dir }}/iso --content iso
  register: add_iso_storage
  failed_when: add_iso_storage.rc != 0 and 'already defined' not in add_iso_storage.stderr
  changed_when: add_iso_storage.rc == 0

# Création de la VM de backtesting
- name: Create backtesting VM
  shell: >
    qm create {{ vm_ids.backtesting }} --name "BacktestingGPU" --memory {{ backtesting_memory }} --cores {{ backtesting_cores }}
    --net0 virtio,bridge=vmbr0 --bios ovmf --machine q35 --cpu host --ostype l26 --agent 1
  args:
    creates: /etc/pve/qemu-server/{{ vm_ids.backtesting }}.conf
  ignore_errors: yes

- name: Add EFI disk to backtesting VM
  shell: qm set {{ vm_ids.backtesting }} --efidisk0 vm-storage:1
  ignore_errors: yes

- name: Add main disk to backtesting VM
  shell: qm set {{ vm_ids.backtesting }} --sata0 vm-storage:{{ backtesting_disk }},ssd=1
  ignore_errors: yes

- name: Set CPU arguments for backtesting VM
  shell: qm set {{ vm_ids.backtesting }} --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"
  ignore_errors: yes

- name: Add CD-ROM with Ubuntu ISO to backtesting VM
  shell: qm set {{ vm_ids.backtesting }} --ide2 iso:iso/ubuntu-22.04.4-live-server-amd64.iso,media=cdrom
  ignore_errors: yes

# Création de la VM de machine learning
- name: Create machine learning VM
  shell: >
    qm create {{ vm_ids.ml }} --name "MachineLearning" --memory {{ ml_memory }} --cores {{ ml_cores }}
    --net0 virtio,bridge=vmbr0 --bios ovmf --machine q35 --cpu host --ostype l26 --agent 1
  args:
    creates: /etc/pve/qemu-server/{{ vm_ids.ml }}.conf
  ignore_errors: yes

- name: Add EFI disk to machine learning VM
  shell: qm set {{ vm_ids.ml }} --efidisk0 vm-storage:1
  ignore_errors: yes

- name: Add main disk to machine learning VM
  shell: qm set {{ vm_ids.ml }} --sata0 vm-storage:{{ ml_disk }},ssd=1
  ignore_errors: yes

- name: Set CPU arguments for machine learning VM
  shell: qm set {{ vm_ids.ml }} --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"
  ignore_errors: yes

- name: Add CD-ROM with Ubuntu ISO to machine learning VM
  shell: qm set {{ vm_ids.ml }} --ide2 iso:iso/ubuntu-22.04.4-live-server-amd64.iso,media=cdrom
  ignore_errors: yes

# Configuration du passthrough GPU pour les VMs
- name: Configure GPU passthrough for VMs
  block:
    - name: Check if GPU exists
      shell: lspci -nnk | grep -i nvidia
      register: gpu_check
      changed_when: false
      ignore_errors: yes

    - name: Configure GPU passthrough for VMs
      include_tasks: gpu-passthrough.yml
      when: gpu_check.rc == 0 and gpu_passthrough | bool
  when: gpu_passthrough | bool
```

# Fichier pour le passthrough GPU

Voici le fichier ansible/playbooks/gpu-passthrough.yml qui gère la configuration du passthrough GPU :

```yaml
---
# Playbook pour la configuration du passthrough GPU

- name: Extract NVIDIA IDs
  shell: lspci -nn | grep -i nvidia | grep -o -P "\[\K[0-9a-f]{4}:[0-9a-f]{4}\]" | tr -d '[]' | sort -u | tr '\n' ',' | sed 's/,$//'
  register: nvidia_ids
  changed_when: false

- name: Configure VFIO for NVIDIA GPUs
  template:
    src: ../../proxmox/configuration/vfio.conf
    dest: /etc/modprobe.d/vfio.conf
    mode: '0644'
  register: vfio_config

- name: Configure KVM for NVIDIA GPUs
  template:
    src: ../../proxmox/configuration/kvm.conf
    dest: /etc/modprobe.d/kvm.conf
    mode: '0644'
  register: kvm_config

- name: Blacklist NVIDIA drivers
  template:
    src: ../../proxmox/configuration/blacklist-nvidia.conf
    dest: /etc/modprobe.d/blacklist-nvidia.conf
    mode: '0644'
  register: blacklist_config

- name: Update initramfs if configurations changed
  shell: update-initramfs -u -k all
  when: vfio_config.changed or kvm_config.changed or blacklist_config.changed

- name: Create script to add GPUs to VMs
  template:
    src: ../../proxmox/templates/configure_gpus.sh.j2
    dest: /usr/local/bin/configure_gpus.sh
    mode: '0755'
  register: gpu_script

- name: Create template for GPU configuration script
  copy:
    dest: ../../proxmox/templates/configure_gpus.sh.j2
    content: |
      #!/bin/bash
      # Script pour configurer le passthrough GPU pour les VMs
      # Généré automatiquement par Ansible - ne pas modifier manuellement
      
      # Arrêter les VMs si elles sont en cours d'exécution
      qm stop {{ vm_ids.backtesting }} 2>/dev/null || true
      qm stop {{ vm_ids.ml }} 2>/dev/null || true
      
      # Configurer les GPUs pour la VM de backtesting
      {% for gpu in gpu_devices %}
      {% if gpu.vm == 'backtesting' %}
      qm set {{ vm_ids.backtesting }} --hostpci{{ loop.index0 }} {{ gpu.id }},{{ gpu.options }}
      {% endif %}
      {% endfor %}
      
      # Configurer les GPUs pour la VM de machine learning
      {% for gpu in gpu_devices %}
      {% if gpu.vm == 'ml' %}
      qm set {{ vm_ids.ml }} --hostpci{{ loop.index0 }} {{ gpu.id }},{{ gpu.options }}
      {% endif %}
      {% endfor %}
      
      echo "Configuration GPU terminée!"
    mode: '0644'
  when: gpu_script is failed

- name: Create script to add GPUs to VMs (retry)
  template:
    src: ../../proxmox/templates/configure_gpus.sh.j2
    dest: /usr/local/bin/configure_gpus.sh
    mode: '0755'
```

# Fichier pour la configuration des conteneurs

Voici le fichier ansible/playbooks/container-setup.yml pour créer et configurer les conteneurs LXC :

```yaml
---
# Playbook pour la création et configuration des conteneurs LXC

- name: Create container storage directory if not exists
  file:
    path: "{{ storage_dir }}/containers"
    state: directory
    mode: '0755'

- name: Add container storage to Proxmox
  shell: pvesm add dir ct-storage --path {{ storage_dir }}/containers --content rootdir
  register: add_ct_storage
  failed_when: add_ct_storage.rc != 0 and 'already defined' not in add_ct_storage.stderr
  changed_when: add_ct_storage.rc == 0

- name: Update container templates
  shell: pveam update
  changed_when: false

- name: Download Debian 12 container template
  shell: pveam download local debian-12-standard_12.7-1_amd64.tar.zst
  register: template_download
  changed_when: template_download.rc == 0 and 'already exists' not in template_download.stdout
  failed_when: template_download.rc != 0 and 'already exists' not in template_download.stdout

# Création du conteneur PostgreSQL
- name: Create PostgreSQL container
  shell: >
    pct create {{ container_ids.db }} local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
    --hostname db-server
    --memory 1024
    --cores 1
    --rootfs ct-storage:20
    --net0 name=eth0,bridge=vmbr0,ip=dhcp
    --onboot 1
  args:
    creates: /etc/pve/lxc/{{ container_ids.db }}.conf
  ignore_errors: yes

- name: Start PostgreSQL container
  shell: pct start {{ container_ids.db }}
  ignore_errors: yes

- name: Wait for PostgreSQL container to start
  wait_for:
    timeout: 10
  delegate_to: localhost

- name: Update packages in PostgreSQL container
  shell: pct exec {{ container_ids.db }} -- bash -c "apt-get update && apt-get upgrade -y"
  ignore_errors: yes

- name: Install PostgreSQL in container
  shell: pct exec {{ container_ids.db }} -- bash -c "apt-get install -y postgresql postgresql-contrib"
  ignore_errors: yes

- name: Enable and start PostgreSQL service
  shell: pct exec {{ container_ids.db }} -- bash -c "systemctl enable postgresql && systemctl start postgresql"
  ignore_errors: yes

- name: Configure PostgreSQL to listen on all interfaces
  shell: pct exec {{ container_ids.db }} -- bash -c "echo \"listen_addresses = '*'\" >> /etc/postgresql/*/main/postgresql.conf"
  ignore_errors: yes

- name: Configure PostgreSQL for external connections
  shell: pct exec {{ container_ids.db }} -- bash -c "echo \"host all all 0.0.0.0/0 md5\" >> /etc/postgresql/*/main/pg_hba.conf"
  ignore_errors: yes

- name: Restart PostgreSQL service
  shell: pct exec {{ container_ids.db }} -- bash -c "systemctl restart postgresql"
  ignore_errors: yes

# Création du conteneur de sauvegarde
- name: Create backup container
  shell: >
    pct create {{ container_ids.backup }} local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
    --hostname backup-server
    --memory 1024
    --cores 1
    --rootfs ct-storage:20
    --net0 name=eth0,bridge=vmbr0,ip=dhcp
    --onboot 1
  args:
    creates: /etc/pve/lxc/{{ container_ids.backup }}.conf
  ignore_errors: yes

- name: Start backup container
  shell: pct start {{ container_ids.backup }}
  ignore_errors: yes

- name: Wait for backup container to start
  wait_for:
    timeout: 10
  delegate_to: localhost

- name: Update packages in backup container
  shell: pct exec {{ container_ids.backup }} -- bash -c "apt-get update && apt-get upgrade -y"
  ignore_errors: yes

- name: Install backup tools in container
  shell: pct exec {{ container_ids.backup }} -- bash -c "apt-get install -y rsync cron"
  ignore_errors: yes

- name: Create mount point for external backup
  shell: pct exec {{ container_ids.backup }} -- bash -c "mkdir -p /mnt/external_backup"
  ignore_errors: yes

- name: Create backup script in container
  copy:
    dest: /tmp/backup-mount.sh
    content: |
      #!/bin/bash
      # Script pour monter le disque externe de sauvegarde
      # À adapter selon votre configuration
      
      DEVICE="/dev/sdX1"  # À modifier selon votre disque
      MOUNT_POINT="/mnt/external_backup"
      
      mkdir -p $MOUNT_POINT
      # Commenter la ligne suivante et configurer correctement avant utilisation
      # mount $DEVICE $MOUNT_POINT || echo "Erreur lors du montage du disque."
      
      # Ajout d'une entrée dans fstab pour le montage automatique
      if ! grep -q "$MOUNT_POINT" /etc/fstab; then
          echo "$DEVICE $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
      fi
    mode: '0755'

- name: Copy backup mount script to container
  shell: pct push {{ container_ids.backup }} /tmp/backup-mount.sh /root/backup-mount.sh
  ignore_errors: yes

- name: Make backup mount script executable
  shell: pct exec {{ container_ids.backup }} -- bash -c "chmod +x /root/backup-mount.sh"
  ignore_errors: yes
```

# Fichier pour la configuration de la VM de backtesting

Voici le fichier ansible/playbooks/backtesting-vm-setup.yml pour configurer l'environnement de backtesting dans la VM :

```yaml
---
# Playbook pour la configuration de l'environnement dans la VM de backtesting

- name: Update package cache
  apt:
    update_cache: yes
  become: yes

- name: Upgrade all packages
  apt:
    upgrade: yes
  become: yes

- name: Install base tools
  apt:
    name:
      - build-essential
      - gcc
      - g++
      - make
      - cmake
      - unzip
      - git
      - curl
      - wget
      - htop
      - nano
      - screen
      - tmux
    state: present
  become: yes

- name: Install Python and related packages
  apt:
    name:
      - python3-pip
      - python3-dev
      - python3-venv
    state: present
  become: yes

- name: Install NVIDIA drivers and CUDA
  block:
    - name: Add graphics drivers PPA
      apt_repository:
        repo: ppa:graphics-drivers/ppa
        state: present
      register: ppa_added

    - name: Update apt cache after adding PPA
      apt:
        update_cache: yes
      when: ppa_added.changed

    - name: Install NVIDIA driver
      apt:
        name: nvidia-driver-550
        state: present

    - name: Download CUDA keyring
      get_url:
        url: https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        dest: /tmp/cuda-keyring_1.1-1_all.deb
        mode: '0644'

    - name: Install CUDA keyring
      apt:
        deb: /tmp/cuda-keyring_1.1-1_all.deb
        state: present

    - name: Update apt cache after adding CUDA repo
      apt:
        update_cache: yes

    - name: Install CUDA toolkit
      apt:
        name: cuda-toolkit-12-3
        state: present
  become: yes
  ignore_errors: yes

- name: Create backtester user
  user:
    name: "{{ users.backtesting.name }}"
    password: "{{ users.backtesting.password | password_hash('sha512') }}"
    shell: /bin/bash
    groups: sudo
    append: yes
  become: yes

- name: Create Python virtual environment
  become: yes
  become_user: "{{ users.backtesting.name }}"
  shell: python3 -m venv ~/venv
  args:
    creates: /home/{{ users.backtesting.name }}/venv

- name: Install Python packages
  become: yes
  become_user: "{{ users.backtesting.name }}"
  pip:
    name: "{{ lookup('file', '../../config/python/requirements-backtesting.txt').splitlines() }}"
    virtualenv: /home/{{ users.backtesting.name }}/venv
  ignore_errors: yes

- name: Create Jupyter configuration directory
  file:
    path: /etc/jupyter
    state: directory
    mode: '0755'
  become: yes

- name: Copy Jupyter configuration
  template:
    src: ../../config/jupyter/jupyter_notebook_config.py
    dest: /etc/jupyter/jupyter_notebook_config.py
    mode: '0644'
  become: yes

- name: Create Jupyter service
  template:
    src: ../../config/systemd/jupyter.service
    dest: /etc/systemd/system/jupyter.service
    mode: '0644'
  vars:
    user: "{{ users.backtesting.name }}"
  become: yes

- name: Start and enable Jupyter service
  systemd:
    name: jupyter
    state: started
    enabled: yes
    daemon_reload: yes
  become: yes

- name: Create project directories
  file:
    path: "/home/{{ users.backtesting.name }}/{{ item }}"
    state: directory
    owner: "{{ users.backtesting.name }}"
    group: "{{ users.backtesting.name }}"
    mode: '0755'
  loop:
    - "projects/data"
    - "projects/strategies"
    - "projects/results"
    - "projects/models"
  become: yes
```

# Fichier installation.md pour la documentation

Voici le fichier doc/installation.md pour guider l'installation de MLENV :

```markdown
# Guide d'installation de MLENV

Ce document détaille les étapes pour installer et configurer l'environnement MLENV sur un serveur Proxmox.

## Prérequis

### Matériel
- Serveur avec CPU compatible IOMMU (Intel VT-d ou AMD-Vi)
- Minimum 16 GB RAM
- SSD pour le système d'exploitation (min 50 GB)
- Cartes GPU NVIDIA (GTX 1660 Super/Ti ou similaires)
- Disque de stockage supplémentaire (SSD ou HDD)

### Logiciels
- ISO Proxmox VE 8.x
- Clé USB bootable
- Accès réseau pour télécharger des packages

## 1. Installation de Proxmox VE

### 1.1 Création de la clé USB d'installation
1. Téléchargez l'ISO Proxmox VE 8.x depuis le [site officiel](https://www.proxmox.com/en/downloads)
2. Créez une clé USB bootable avec l'outil de votre choix (Rufus sous Windows, dd sous Linux)

### 1.2 Installation de Proxmox
1. Démarrez le serveur depuis la clé USB
2. Suivez l'assistant d'installation :
   - Acceptez le contrat de licence
   - Sélectionnez le disque pour l'installation (SSD)
   - Définissez le fuseau horaire, le pays et la disposition du clavier
   - Définissez un mot de passe root et une adresse e-mail
   - Configurez le réseau (nom d'hôte, adresse IP, passerelle, serveur DNS)
3. Terminez l'installation et redémarrez
4. Accédez à l'interface web Proxmox : https://IP-DU-SERVEUR:8006

## 2. Configuration post-installation

### 2.1 Mise à jour de Proxmox

Connectez-vous au serveur via SSH et exécutez :

```bash
apt update
apt install -y git ansible
```

### 2.2 Clonage du dépôt MLENV

```bash
cd /root
git clone https://github.com/votre-username/mlenv.git
cd mlenv
```

### 2.3 Configuration avec Ansible

1. Copiez et personnalisez le fichier d'inventaire :
   ```bash
   cd ansible
   cp inventory/hosts.example.yml inventory/hosts.yml
   nano inventory/hosts.yml  # Ajustez selon votre environnement
   ```

2. Lancez le playbook principal :
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml
   ```

3. Redémarrez le serveur pour appliquer la configuration IOMMU :
   ```bash
   reboot
   ```

## 3. Création et configuration des VMs

### 3.1 Installation de l'OS dans les VMs

1. Accédez à l'interface web Proxmox
2. Démarrez la VM 100 (BacktestingGPU)
3. Installez Ubuntu 22.04 Server via la console
4. Répétez pour la VM 101 (MachineLearning)

### 3.2 Configuration du passthrough GPU

Après avoir installé l'OS dans les VMs, exécutez le script de configuration GPU :

```bash
/usr/local/bin/configure_gpus.sh
```

### 3.3 Configuration de l'environnement dans les VMs

Utilisez Ansible pour configurer les environnements Python, CUDA, etc. :

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/backtesting-vm-setup.yml
ansible-playbook -i inventory/hosts.yml playbooks/ml-vm-setup.yml
```

## 4. Configuration des conteneurs LXC

Les conteneurs sont automatiquement créés et configurés par Ansible. Pour vérifier :

```bash
pct list
```

## 5. Vérification de l'installation

### 5.1 Vérification de Proxmox
- Accédez à l'interface web : https://IP-DU-SERVEUR:8006
- Vérifiez que les VMs et conteneurs sont bien créés

### 5.2 Vérification du passthrough GPU
Dans les VMs, exécutez :
```bash
nvidia-smi
```

### 5.3 Vérification de Jupyter
Accédez à Jupyter via le navigateur :
- VM Backtesting : http://IP-VM-BACKTESTING:8888
- VM Machine Learning : http://IP-VM-ML:8888

## Dépannage

Si vous rencontrez des problèmes, consultez le document [troubleshooting.md](troubleshooting.md).

Pour une réinitialisation complète, consultez [reset-environment.md](reset-environment.md).
```

# Script PowerShell de personnalisation de l'environnement

Voici le fichier Personalize-Environment.ps1 pour adapter tous les fichiers à votre environnement spécifique :

```powershell
<#
.SYNOPSIS
    Script pour personnaliser l'environnement MLENV avec vos variables locales
.DESCRIPTION
    Ce script remplace les variables génériques dans le projet MLENV par vos valeurs locales
.NOTES
    Version:        1.0
    Author:         MLENV Project
    Creation Date:  2025-03-15
#>

# Variables à personnaliser
$server_hostname = "predatorx"  # Nom d'hôte du serveur Proxmox
$server_ip = "192.168.1.100"    # Adresse IP du serveur Proxmox
$backtesting_ip = "192.168.1.101"  # Adresse IP de la VM de backtesting
$ml_ip = "192.168.1.102"        # Adresse IP de la VM de machine learning
$db_container_ip = "192.168.1.201"  # Adresse IP du conteneur de base de données
$backup_container_ip = "192.168.1.202"  # Adresse IP du conteneur de sauvegarde

# Variables GPU - Ajustez selon votre configuration
$gpu_ids = @(
    "01:00.0",
    "02:00.0",
    "03:00.0",
    "04:00.0",
    "06:00.0",
    "07:00.0",
    "08:00.0",
    "09:00.0"
)

# Nombre de GPUs à attribuer à chaque VM
$backtesting_gpu_count = 2
$ml_gpu_count = 6

# Fonction pour remplacer les variables dans un fichier
function Replace-Variables {
    param(
        [string]$FilePath
    )
    
    if (Test-Path -Path $FilePath) {
        $content = Get-Content -Path $FilePath -Raw
        
        # Remplacer les variables de base
        $content = $content -replace '{{ server_hostname }}', $server_hostname
        $content = $content -replace '{{ server_ip }}', $server_ip
        $content = $content -replace '{{ backtesting_ip }}', $backtesting_ip
        $content = $content -replace '{{ ml_ip }}', $ml_ip
        $content = $content -replace '{{ db_container_ip }}', $db_container_ip
        $content = $content -replace '{{ backup_container_ip }}', $backup_container_ip
        
        # Remplacer les variables de GPU dans all.yml
        if ($FilePath.EndsWith("all.yml") -or $FilePath.EndsWith("hosts.yml")) {
            # Générer la configuration des GPU dynamiquement
            $gpu_devices = ""
            for ($i = 0; $i -lt $gpu_ids.Length; $i++) {
                $vm = if ($i -lt $backtesting_gpu_count) { "backtesting" } else { "ml" }
                $options = if (($i -eq 0 -and $vm -eq "backtesting") -or ($i -eq $backtesting_gpu_count -and $vm -eq "ml")) {
                    "pcie=1,x-vga=on"
                } else {
                    "pcie=1"
                }
                
                $gpu_devices += "  - id: `"$($gpu_ids[$i])`"`n"
                $gpu_devices += "    vm: $vm`n"
                $gpu_devices += "    options: `"$options`"`n"
            }
            
            $content = $content -replace '(?s)gpu_devices:.*?(\n\w)', "gpu_devices:`n$gpu_devices`$1"
        }
        
        # Enregistrer les modifications
        Set-Content -Path $FilePath -Value $content
        Write-Host "Variables remplacées dans $FilePath" -ForegroundColor Green
    }
    else {
        Write-Host "Le fichier $FilePath n'existe pas" -ForegroundColor Red
    }
}

# Fichiers à personnaliser
$filesToPersonalize = @(
    "ansible/inventory/hosts.yml",
    "ansible/inventory/group_vars/all.yml",
    "README.md"
)

# Créer hosts.yml à partir de l'exemple
if (-not (Test-Path -Path "ansible/inventory/hosts.yml") -and (Test-Path -Path "ansible/inventory/hosts.example.yml")) {
    Copy-Item -Path "ansible/inventory/hosts.example.yml" -Destination "ansible/inventory/hosts.yml"
    Write-Host "Fichier hosts.yml créé à partir de l'exemple" -ForegroundColor Green
}

# Remplacer les variables dans chaque fichier
foreach ($file in $filesToPersonalize) {
    Replace-Variables -FilePath $file
}

# Configure GPU devices in the template file
$template_path = "proxmox/templates/configure_gpus.sh.j2"

if (Test-Path -Path $template_path) {
    $template_content = Get-Content -Path $template_path -Raw
    
    # Générer les commandes GPU pour la VM backtesting
    $backtesting_gpu_commands = ""
    for ($i = 0; $i -lt $backtesting_gpu_count; $i++) {
        $options = if ($i -eq 0) { "pcie=1,x-vga=on" } else { "pcie=1" }
        $backtesting_gpu_commands += "qm set {{ vm_ids.backtesting }} --hostpci$i $($gpu_ids[$i]),$options`n"
    }
    
    # Générer les commandes GPU pour la VM ML
    $ml_gpu_commands = ""
    for ($i = 0; $i -lt $ml_gpu_count; $i++) {
        $options = if ($i -eq 0) { "pcie=1,x-vga=on" } else { "pcie=1" }
        $ml_gpu_commands += "qm set {{ vm_ids.ml }} --hostpci$i $($gpu_ids[$i + $backtesting_gpu_count]),$options`n"
    }
    
    # Remplacer dans le template
    $template_content = $template_content -replace '(?s)# Configurer les GPUs pour la VM de backtesting.*?# Configurer les GPUs pour la VM de machine learning', "# Configurer les GPUs pour la VM de backtesting`n$backtesting_gpu_commands`n# Configurer les GPUs pour la VM de machine learning"
    $template_content = $template_content -replace '(?s)# Configurer les GPUs pour la VM de machine learning.*?echo "Configuration GPU', "# Configurer les GPUs pour la VM de machine learning`n$ml_gpu_commands`n`necho "Configuration GPU"
    
    # Enregistrer le template modifié
    Set-Content -Path $template_path -Value $template_content
    Write-Host "Template de configuration GPU personnalisé" -ForegroundColor Green
}

Write-Host "Personnalisation de l'environnement terminée!" -ForegroundColor Green
Write-Host "Vos fichiers ont été mis à jour avec vos variables locales." -ForegroundColor Green
Write-Host ""
Write-Host "Prochaines étapes:" -ForegroundColor Yellow
Write-Host "1. Poussez les modifications vers votre dépôt GitHub :" -ForegroundColor Cyan
Write-Host "   git add ."
Write-Host "   git commit -m 'Configuration personnalisée pour mon environnement'"
Write-Host "   git push origin main"
Write-Host ""
Write-Host "2. Sur le serveur Proxmox, clonez votre dépôt et exécutez Ansible :" -ForegroundColor Cyan
Write-Host "   git clone https://github.com/votre-username/mlenv.git"
Write-Host "   cd mlenv/ansible"
Write-Host "   ansible-playbook -i inventory/hosts.yml playbooks/site.yml"
```

Voici maintenant le fichier variables.yml qui sera utilisé comme base pour la personnalisation :

```yaml
---
# Variables globales pour le projet MLENV
# À personnaliser selon votre environnement

# Variables serveur
server_hostname: "{{ server_hostname }}"
server_ip: "{{ server_ip }}"

# Variables stockage
storage_dir: /mnt/vmstorage
storage_type: directory  # Options: zfs, lvm, directory

# Variables VMs
vm_ids:
  backtesting: 100
  ml: 101
  web: 102

backtesting_ip: "{{ backtesting_ip }}"
backtesting_cores: 2
backtesting_memory: 8192
backtesting_disk: 40

ml_ip: "{{ ml_ip }}"
ml_cores: 2
ml_memory: 8192
ml_disk: 40

# Variables conteneurs
container_ids:
  db: 200
  backup: 201

db_container_ip: "{{ db_container_ip }}"
backup_container_ip: "{{ backup_container_ip }}"

# Variables GPU
gpu_passthrough: true
gpu_devices:
  - id: "01:00.0"
    vm: backtesting
    options: "pcie=1,x-vga=on"
  - id: "02:00.0"
    vm: backtesting
    options: "pcie=1"
  - id: "03:00.0"
    vm: ml
    options: "pcie=1,x-vga=on"
  - id: "04:00.0"
    vm: ml
    options: "pcie=1"
  - id: "06:00.0"
    vm: ml
    options: "pcie=1"
  - id: "07:00.0"
    vm: ml
    options: "pcie=1"
  - id: "08:00.0"
    vm: ml
    options: "pcie=1"
  - id: "09:00.0"
    vm: ml
    options: "pcie=1"

# Variables utilisateurs
users:
  backtesting:
    name: backtester
    password: "backtester"  # À changer pour la production
  ml:
    name: aitrader
    password: "aitrader"    # À changer pour la production

# Variables Jupyter
jupyter_port: 8888
jupyter_password_hash: ""  # Générer avec: python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
```

Ces fichiers constituent une base solide pour reconstruire votre environnement MLENV. 
Pour continuer la configuration et adapter d'autres aspects spécifiques, vous pouvez générer d'autres fichiers selon vos besoins. 
Faut-il que je génère d'autres fichiers pour compléter le projet ?
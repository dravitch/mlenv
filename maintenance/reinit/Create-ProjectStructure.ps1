# Script PowerShell pour générer la structure complète du projet MLENV
# À exécuter depuis la racine du projet

# Fonction pour l'affichage des messages
function Log-Message {
    param (
        [string]$Message
    )

    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor Blue
}

function Log-Success {
    param (
        [string]$Message
    )

    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor Green
}

# Vérifier si le répertoire existe déjà
if (-not (Test-Path -Path "mlenv")) {
    Log-Message "Création du répertoire mlenv..."
    New-Item -Path "mlenv" -ItemType Directory -Force | Out-Null
}

Set-Location -Path "mlenv"

# Création des répertoires principaux
Log-Message "Création des répertoires principaux..."
$directories = @(
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

foreach ($dir in $directories) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
}

# Copie des fichiers existants s'ils existent
if (Test-Path -Path "../proxmox/post-install.sh") {
    Log-Message "Copie des scripts Proxmox existants..."
    Copy-Item -Path "../proxmox/post-install.sh" -Destination "proxmox/"
    Copy-Item -Path "../proxmox/progressive-gpu-passthrough.sh" -Destination "proxmox/"
}

if (Test-Path -Path "../storage/setup-m2-storage.sh") {
    Log-Message "Copie des scripts de stockage existants..."
    Copy-Item -Path "../storage/setup-m2-storage.sh" -Destination "storage/"
}

if (Test-Path -Path "../ansible/playbooks/site.yml") {
    Log-Message "Copie des playbooks Ansible existants..."
    Copy-Item -Path "../ansible/playbooks/*.yml" -Destination "ansible/playbooks/"
    Copy-Item -Path "../ansible/inventory/hosts.yml" -Destination "ansible/inventory/"
    Copy-Item -Path "../ansible/inventory/group_vars/all.yml" -Destination "ansible/inventory/group_vars/"
}

# Création des fichiers de configuration VFIO et KVM
Log-Message "Création des fichiers de configuration VFIO et KVM..."

$vfioConfig = @"
# Configuration VFIO pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/vfio.conf

# Liste des IDs des GPUs NVIDIA à passer en passthrough
# Format: vendorID:deviceID
options vfio-pci ids=10de:XXXX
"@

$kvmConfig = @"
# Configuration KVM pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/kvm.conf

# Ignorer les MSRs pour éviter les erreurs avec les cartes NVIDIA
options kvm ignore_msrs=1 report_ignored_msrs=0
"@

$blacklistNvidiaConfig = @"
# Configuration pour blacklister les pilotes NVIDIA natifs sur l'hôte
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/blacklist-nvidia.conf

# Blacklist tous les pilotes NVIDIA pour permettre le passthrough
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
"@

Set-Content -Path "proxmox/configuration/vfio.conf" -Value $vfioConfig
Set-Content -Path "proxmox/configuration/kvm.conf" -Value $kvmConfig
Set-Content -Path "proxmox/configuration/blacklist-nvidia.conf" -Value $blacklistNvidiaConfig

# Création du script de restauration
Log-Message "Création du script de restauration..."

$restoreBootScript = @"
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
"@

Set-Content -Path "scripts/recovery/restore-boot.sh" -Value $restoreBootScript

# Création des fichiers de configuration Python
Log-Message "Création des fichiers de configuration Python..."

$backtestingRequirements = @"
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
"@

$mlRequirements = @"
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
"@

Set-Content -Path "config/python/requirements-backtesting.txt" -Value $backtestingRequirements
Set-Content -Path "config/python/requirements-ml.txt" -Value $mlRequirements

# Création des fichiers de service systemd
Log-Message "Création des fichiers de service systemd..."

$jupyterService = @"
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
"@

Set-Content -Path "config/systemd/jupyter.service" -Value $jupyterService

# Création du fichier de configuration Jupyter
Log-Message "Création du fichier de configuration Jupyter..."

$jupyterConfig = @"
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Générer un mot de passe sécurisé avec:
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
c.NotebookApp.password = ''  # Remplacer par le hash généré
"@

Set-Content -Path "config/jupyter/jupyter_notebook_config.py" -Value $jupyterConfig

# Création des scripts de base
Log-Message "Création des scripts utilitaires..."

$backupScript = @"
#!/bin/bash
# Script de sauvegarde pour PredatorX
# À exécuter quotidiennement via cron

DATE=$(date +%Y-%m-%d)
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
"@

$maintenanceScript = @"
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
"@

Set-Content -Path "scripts/backup.sh" -Value $backupScript
Set-Content -Path "scripts/maintenance.sh" -Value $maintenanceScript

# Création du script Ansible pour générer les rôles
Log-Message "Création du script pour générer les rôles Ansible..."

$createAnsibleRolesScript = @"
#!/bin/bash
# Script pour créer la structure des rôles Ansible
# À exécuter depuis le répertoire ansible/

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "\${BLUE}[\$(date '+%Y-%m-%d %H:%M:%S')]\${NC} \$1"
}

success() {
    echo -e "\${GREEN}[\$(date '+%Y-%m-%d %H:%M:%S')]\${NC} \$1"
}

# Liste des rôles à créer
ROLES=(
    "common"
    "nvidia-drivers"
    "python-env"
    "jupyter"
    "backtesting"
    "ml-tools"
    "monitoring"
)

# Création du répertoire roles s'il n'existe pas
if [ ! -d "roles" ]; then
    log "Création du répertoire roles..."
    mkdir -p roles
fi

# Création de la structure pour chaque rôle
for role in "\${ROLES[@]}"; do
    log "Création de la structure pour le rôle \$role..."

    # Création des répertoires standard pour le rôle
    mkdir -p "roles/\$role/"{tasks,handlers,templates,files,vars,defaults,meta}

    # Création du fichier main.yml dans tasks
    cat > "roles/\$role/tasks/main.yml" << EOF
---
# Tâches principales pour le rôle \$role
# Ce fichier sera appelé automatiquement lorsque le rôle est inclus
EOF

    # Création du fichier main.yml dans handlers
    cat > "roles/\$role/handlers/main.yml" << EOF
---
# Handlers pour le rôle \$role
EOF

    # Création du fichier main.yml dans defaults
    cat > "roles/\$role/defaults/main.yml" << EOF
---
# Valeurs par défaut pour le rôle \$role
EOF

    # Création du fichier main.yml dans vars
    cat > "roles/\$role/vars/main.yml" << EOF
---
# Variables spécifiques pour le rôle \$role
EOF

    # Création du fichier meta/main.yml
    cat > "roles/\$role/meta/main.yml" << EOF
---
# Métadonnées pour le rôle \$role
galaxy_info:
  role_name: \$role
  author: PredatorX Admin
  description: Role for configuring \$role on PredatorX
  license: MIT
  min_ansible_version: 2.9
  platforms:
    - name: Debian
      versions:
        - bullseye
    - name: Ubuntu
      versions:
        - jammy

dependencies: []
EOF

    success "Structure du rôle \$role créée avec succès"
done

success "Tous les rôles ont été créés avec succès!"
log "Pour utiliser ces rôles, modifiez le playbook principal (site.yml) pour inclure les rôles au lieu d'inclure les tâches."
log "Exemple: roles: ['common', 'nvidia-drivers', 'python-env', 'jupyter']"
"@

Set-Content -Path "ansible/create-ansible-roles.sh" -Value $createAnsibleRolesScript

# Création des templates pour les rôles Ansible
Log-Message "Création des templates pour les rôles Ansible..."
New-Item -Path "ansible/roles/jupyter/templates" -ItemType Directory -Force | Out-Null

$jupyterConfigTemplate = @"
# Configuration Jupyter générée par Ansible
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = {{ jupyter_port | default(8888) }}
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = '{{ jupyter_password_hash }}'  # À définir dans les variables
"@

$jupyterServiceTemplate = @"
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
User={{ user_name }}
ExecStart=/home/{{ user_name }}/venv/bin/jupyter lab --config=/etc/jupyter/jupyter_notebook_config.py
WorkingDirectory=/home/{{ user_name }}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"@

Set-Content -Path "ansible/roles/jupyter/templates/jupyter_notebook_config.py.j2" -Value $jupyterConfigTemplate
Set-Content -Path "ansible/roles/jupyter/templates/jupyter.service.j2" -Value $jupyterServiceTemplate

# Création de la documentation
Log-Message "Création des fichiers de documentation..."
if (Test-Path -Path "../doc/installation.md") {
    Copy-Item -Path "../doc/installation.md" -Destination "doc/"
}

# Pour les autres fichiers de documentation
$docFiles = @("usage.md", "maintenance.md", "troubleshooting.md")
foreach ($doc in $docFiles) {
    if (-not (Test-Path -Path "doc/$doc")) {
        New-Item -Path "doc/$doc" -ItemType File -Force | Out-Null
    }
}

# Création des répertoires pour les rôles Ansible vides
Log-Message "Création des répertoires pour les rôles Ansible..."
$ansibleRoles = @("common", "nvidia-drivers", "python-env", "jupyter", "backtesting", "ml-tools", "monitoring")
foreach ($role in $ansibleRoles) {
    New-Item -Path "ansible/roles/$role/tasks" -ItemType Directory -Force | Out-Null
    Set-Content -Path "ansible/roles/$role/tasks/main.yml" -Value "---"
}

# Message final
Log-Success "Structure du projet MLENV créée avec succès!"
Log-Message "Pour générer la structure complète des rôles Ansible, si vous êtes sous Linux ou utilisez WSL, exécutez:"
Log-Message "  cd ansible && ./create-ansible-roles.sh"

# Retour au répertoire parent
Set-Location -Path ".."
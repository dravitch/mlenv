#!/bin/bash
# Script pour générer la structure complète du projet MLENV
# À exécuter depuis la racine du projet

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Vérifier si le répertoire existe déjà
if [ ! -d "mlenv" ]; then
    log "Création du répertoire mlenv..."
    mkdir -p mlenv
fi

cd mlenv

# Création des répertoires principaux
log "Création des répertoires principaux..."
mkdir -p proxmox/configuration
mkdir -p storage
mkdir -p ansible/inventory/group_vars
mkdir -p ansible/playbooks
mkdir -p ansible/roles
mkdir -p scripts/recovery
mkdir -p config/jupyter
mkdir -p config/systemd
mkdir -p config/python
mkdir -p doc

# Copie des fichiers existants s'ils existent
if [ -f "../proxmox/post-install.sh" ]; then
    log "Copie des scripts Proxmox existants..."
    cp ../proxmox/post-install.sh proxmox/
    cp ../proxmox/progressive-gpu-passthrough.sh proxmox/
fi

if [ -f "../storage/setup-m2-storage.sh" ]; then
    log "Copie des scripts de stockage existants..."
    cp ../storage/setup-m2-storage.sh storage/
fi

if [ -f "../ansible/playbooks/site.yml" ]; then
    log "Copie des playbooks Ansible existants..."
    cp ../ansible/playbooks/*.yml ansible/playbooks/
    cp ../ansible/inventory/hosts.yml ansible/inventory/
    cp ../ansible/inventory/group_vars/all.yml ansible/inventory/group_vars/
fi

# Création des fichiers de configuration VFIO et KVM
log "Création des fichiers de configuration VFIO et KVM..."
cat > proxmox/configuration/vfio.conf << 'EOF'
# Configuration VFIO pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/vfio.conf

# Liste des IDs des GPUs NVIDIA à passer en passthrough
# Format: vendorID:deviceID
options vfio-pci ids=10de:XXXX
EOF

cat > proxmox/configuration/kvm.conf << 'EOF'
# Configuration KVM pour le passthrough GPU NVIDIA
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/kvm.conf

# Ignorer les MSRs pour éviter les erreurs avec les cartes NVIDIA
options kvm ignore_msrs=1 report_ignored_msrs=0
EOF

cat > proxmox/configuration/blacklist-nvidia.conf << 'EOF'
# Configuration pour blacklister les pilotes NVIDIA natifs sur l'hôte
# Ce fichier est utilisé comme template pour la configuration dans /etc/modprobe.d/blacklist-nvidia.conf

# Blacklist tous les pilotes NVIDIA pour permettre le passthrough
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF

# Création du script de restauration
log "Création du script de restauration..."
cat > scripts/recovery/restore-boot.sh << 'EOF'
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
EOF

chmod +x scripts/recovery/restore-boot.sh

# Création des fichiers de configuration Python
log "Création des fichiers de configuration Python..."
cat > config/python/requirements-backtesting.txt << 'EOF'
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
EOF

cat > config/python/requirements-ml.txt << 'EOF'
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
EOF

# Création des fichiers de service systemd
log "Création des fichiers de service systemd..."
cat > config/systemd/jupyter.service << 'EOF'
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
EOF

# Création du fichier de configuration Jupyter
log "Création du fichier de configuration Jupyter..."
cat > config/jupyter/jupyter_notebook_config.py << 'EOF'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Générer un mot de passe sécurisé avec:
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
c.NotebookApp.password = ''  # Remplacer par le hash généré
EOF

# Création des scripts de base
log "Création des scripts utilitaires..."
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
# Script de sauvegarde pour PredatorX
# À exécuter quotidiennement via cron

DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/mnt/vmstorage/backups"
LOG_FILE="/var/log/pve-backup/backup-${DATE}.log"

mkdir -p /var/log/pve-backup
echo "Démarrage des sauvegardes: $(date)" | tee -a "$LOG_FILE"

# Sauvegarde des VMs
for VM_ID in $(qm list | tail -n+2 | awk '{print $1}')
do
    echo "Sauvegarde de la VM $VM_ID..." | tee -a "$LOG_FILE"
    vzdump $VM_ID --compress zstd --mode snapshot --storage backup | tee -a "$LOG_FILE"
done

# Sauvegarde des conteneurs
for CT_ID in $(pct list | tail -n+2 | awk '{print $1}')
do
    echo "Sauvegarde du conteneur $CT_ID..." | tee -a "$LOG_FILE"
    vzdump $CT_ID --compress zstd --mode snapshot --storage backup | tee -a "$LOG_FILE"
done

# Conservation des 7 derniers jours de logs uniquement
find /var/log/pve-backup -name "backup-*.log" -mtime +7 -delete

echo "Sauvegardes terminées: $(date)" | tee -a "$LOG_FILE"
EOF

chmod +x scripts/backup.sh

cat > scripts/maintenance.sh << 'EOF'
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
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
    echo "ALERTE: L'espace disque sur / est à $DISK_USAGE%" | mail -s "Alerte espace disque sur PredatorX" root
fi

# Mise à jour de l'hôte
apt update && apt list --upgradable
EOF

chmod +x scripts/maintenance.sh

# Création du script Ansible pour générer les rôles
log "Création du script pour générer les rôles Ansible..."
cat > ansible/create-ansible-roles.sh << 'EOF'
#!/bin/bash
# Script pour créer la structure des rôles Ansible
# À exécuter depuis le répertoire ansible/

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
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
for role in "${ROLES[@]}"; do
    log "Création de la structure pour le rôle $role..."

    # Création des répertoires standard pour le rôle
    mkdir -p "roles/$role/"{tasks,handlers,templates,files,vars,defaults,meta}

    # Création du fichier main.yml dans tasks
    cat > "roles/$role/tasks/main.yml" << EOF
---
# Tâches principales pour le rôle $role
# Ce fichier sera appelé automatiquement lorsque le rôle est inclus
EOF

    # Création du fichier main.yml dans handlers
    cat > "roles/$role/handlers/main.yml" << EOF
---
# Handlers pour le rôle $role
EOF

    # Création du fichier main.yml dans defaults
    cat > "roles/$role/defaults/main.yml" << EOF
---
# Valeurs par défaut pour le rôle $role
EOF

    # Création du fichier main.yml dans vars
    cat > "roles/$role/vars/main.yml" << EOF
---
# Variables spécifiques pour le rôle $role
EOF

    # Création du fichier meta/main.yml
    cat > "roles/$role/meta/main.yml" << EOF
---
# Métadonnées pour le rôle $role
galaxy_info:
  role_name: $role
  author: PredatorX Admin
  description: Role for configuring $role on PredatorX
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

    success "Structure du rôle $role créée avec succès"
done

success "Tous les rôles ont été créés avec succès!"
log "Pour utiliser ces rôles, modifiez le playbook principal (site.yml) pour inclure les rôles au lieu d'inclure les tâches."
log "Exemple: roles: ['common', 'nvidia-drivers', 'python-env', 'jupyter']"
EOF

chmod +x ansible/create-ansible-roles.sh

# Création des templates pour les rôles Ansible
log "Création des templates pour les rôles Ansible..."
mkdir -p ansible/roles/jupyter/templates

cat > ansible/roles/jupyter/templates/jupyter_notebook_config.py.j2 << 'EOF'
# Configuration Jupyter générée par Ansible
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = {{ jupyter_port | default(8888) }}
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = '{{ jupyter_password_hash }}'  # À définir dans les variables
EOF

cat > ansible/roles/jupyter/templates/jupyter.service.j2 << 'EOF'
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
EOF

# Création de la documentation
log "Création des fichiers de documentation..."
cp ../doc/installation.md doc/

# Pour les autres fichiers de documentation
for doc_file in usage.md maintenance.md troubleshooting.md; do
    if [ ! -f "doc/$doc_file" ]; then
        touch "doc/$doc_file"
    fi
done

# Création des répertoires pour les rôles Ansible vides
log "Création des répertoires pour les rôles Ansible..."
for role in common nvidia-drivers python-env jupyter backtesting ml-tools monitoring; do
    mkdir -p "ansible/roles/$role/tasks"
    echo "---" > "ansible/roles/$role/tasks/main.yml"
done

# Message final
success "Structure du projet MLENV créée avec succès!"
log "Pour générer la structure complète des rôles Ansible, exécutez:"
log "  cd ansible && ./create-ansible-roles.sh"
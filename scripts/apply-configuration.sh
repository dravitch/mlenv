#!/bin/bash
# Script pour appliquer la configuration depuis le fichier .env
# Génère les fichiers de configuration nécessaires pour le projet MLENV
# À exécuter depuis la racine du projet

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    exit 1
}

# Vérifier si le script est exécuté depuis la racine du projet
if [ ! -f ".env.example" ] && [ ! -d "ansible" ]; then
    error "Ce script doit être exécuté depuis la racine du projet MLENV"
fi

# Vérifier si le fichier .env existe
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        log "Fichier .env non trouvé. Création à partir de .env.example..."
        cp .env.example .env
        warning "Veuillez éditer le fichier .env avec vos paramètres personnalisés"
        warning "Puis exécutez à nouveau ce script"
        exit 0
    else
        error "Fichier .env.example non trouvé. Impossible de créer la configuration."
    fi
fi

# Création des répertoires nécessaires
log "Création des répertoires de configuration..."
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

# Générer les fichiers d'inventaire Ansible
log "Génération des fichiers d'inventaire Ansible..."
if [ -f "scripts/update-inventory.sh" ]; then
    bash scripts/update-inventory.sh
else
    error "Le script update-inventory.sh est manquant. Impossible de générer l'inventaire."
fi

# Générer les configurations VFIO pour GPU passthrough
log "Génération des configurations GPU passthrough..."
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

# Générer la configuration Jupyter
log "Génération de la configuration Jupyter..."
cat > config/jupyter/jupyter_notebook_config.py << 'EOF'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Générer un mot de passe sécurisé avec:
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
c.NotebookApp.password = ''  # Remplacer par le hash généré
EOF

# Générer les fichiers requirements Python
log "Génération des fichiers requirements Python..."
cat > config/python/requirements-backtesting.txt << 'EOF'
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

# Générer le service systemd pour Jupyter
log "Génération du service systemd pour Jupyter..."
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

# Générer le script de restauration d'urgence
log "Génération du script de restauration d'urgence..."
cat > scripts/recovery/restore-boot.sh << 'EOF'
#!/bin/bash
# Script de secours pour restaurer la configuration de démarrage après un échec GPU passthrough

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

# Rendre tous les scripts exécutables
log "Permissions d'exécution pour les scripts..."
find scripts -name "*.sh" -exec chmod +x {} \;
find proxmox -name "*.sh" -exec chmod +x {} \;
find storage -name "*.sh" -exec chmod +x {} \;

# Vérifier si des templates VM JSON existent pour migration
if [ -d "proxmox/vm-templates" ]; then
    log "Migration des templates VM vers le format Ansible..."
    mkdir -p proxmox/vm-templates-old
    mv proxmox/vm-templates/* proxmox/vm-templates-old/
    success "Les anciens templates JSON ont été déplacés vers proxmox/vm-templates-old"
    warning "Ces templates sont désormais remplacés par les playbooks Ansible dans ansible/playbooks/"
fi

success "Configuration appliquée avec succès!"
log "Votre projet MLENV est maintenant configuré. Vous pouvez commencer le déploiement."
log "Étapes suivantes recommandées:"
log "1. Vérifiez les paramètres dans le fichier .env"
log "2. Exécutez: cd ansible && ansible-playbook playbooks/site.yml"
log "3. Suivez les instructions à l'écran pour finaliser l'installation"
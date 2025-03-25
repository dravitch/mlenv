#!/bin/bash
# Script d'installation amélioré pour la VM de backtesting
# À exécuter après l'installation d'Ubuntu Server sur la VM

set -e  # Arrêter le script en cas d'erreur

# Fonction d'affichage des messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root" >&2
    exit 1
fi

# Mise à jour du système
log "Mise à jour du système..."
apt-get update && apt-get upgrade -y

# Installation des outils de base
log "Installation des outils de base..."
apt-get install -y build-essential gcc g++ make cmake unzip git curl wget htop nano screen tmux

# Installation des pilotes NVIDIA
log "Installation des pilotes NVIDIA..."
apt-get install -y software-properties-common
add-apt-repository -y ppa:graphics-drivers/ppa
apt-get update

# Installation du pilote NVIDIA
apt-get install -y nvidia-driver

# Installation de CUDA
log "Installation de CUDA..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update
apt-get install -y cuda-toolkit-12-3

# Vérification de l'installation NVIDIA
log "Vérification de l'installation NVIDIA..."
nvidia-smi || log "Erreur lors de la détection GPU NVIDIA - un redémarrage pourrait être nécessaire"

# Installation des dépendances pour pytables et autres packages
log "Installation des dépendances système pour les bibliothèques Python..."
apt-get install -y libhdf5-serial-dev python3-dev python3-pip python3-venv

# Création d'un utilisateur pour le backtesting
log "Création d'un utilisateur pour le backtesting..."
useradd -m -s /bin/bash backtester
echo "backtester:backtester" | chpasswd  # Mot de passe temporaire, à changer
usermod -aG sudo backtester

# Création d'un répertoire persistant pour les fichiers de configuration
mkdir -p /opt/trading/config
chown -R backtester:backtester /opt/trading

# Création du fichier requirements.txt
cat > /opt/trading/config/requirements.txt << EOF
numpy
pandas
scipy
matplotlib
seaborn
scikit-learn
statsmodels
tables
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

# Création d'un script d'installation des bibliothèques Python
cat > /opt/trading/config/setup_python_env.sh << 'EOF'
#!/bin/bash
# Script d'installation des bibliothèques Python pour le backtesting

set -e  # Arrêter le script en cas d'erreur

echo "Création d'un environnement Python virtuel..."
python3 -m venv ~/venv

echo "Activation de l'environnement virtuel..."
source ~/venv/bin/activate

echo "Mise à jour de pip..."
pip install --upgrade pip

echo "Installation des bibliothèques requises..."
pip install -r /opt/trading/config/requirements.txt

echo "Sauvegarde de l'environnement final..."
pip freeze > ~/requirements_installed.txt

echo "Installation de l'environnement Python terminée!"
EOF

# Ajustement des permissions
chmod +x /opt/trading/config/setup_python_env.sh
chown backtester:backtester /opt/trading/config/setup_python_env.sh

# Exécution du script d'installation des bibliothèques Python
log "Installation des bibliothèques Python..."
su - backtester -c "/opt/trading/config/setup_python_env.sh"

# Configuration de Jupyter
log "Configuration de Jupyter..."
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = 'sha1:74ba40f8a388:c913541b7ee99d15d5ed31d4226bf7838f83a50e'  # Mot de passe temporaire à changer
EOF

# Création d'un service systemd pour Jupyter
cat > /etc/systemd/system/jupyter.service << EOF
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
User=backtester
ExecStart=/home/backtester/venv/bin/jupyter lab --config=/etc/jupyter/jupyter_notebook_config.py
WorkingDirectory=/home/backtester
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Activation et démarrage du service
systemctl enable jupyter.service
systemctl start jupyter.service

# Configuration du pare-feu
log "Configuration du pare-feu..."
apt-get install -y ufw
ufw allow ssh
ufw allow 8888/tcp  # Port Jupyter
ufw allow 5432/tcp  # Port PostgreSQL
ufw --force enable

# Création des répertoires de projet
log "Création des répertoires de projet..."
su - backtester -c "
mkdir -p ~/projects/data
mkdir -p ~/projects/strategies
mkdir -p ~/projects/results
mkdir -p ~/projects/models
"

# Script de test pour vérifier l'installation
cat > /home/backtester/test_environment.py << 'EOF'
#!/usr/bin/env python3
"""
Script de test pour vérifier l'environnement de backtesting
"""
import sys
import subprocess
from importlib import import_module

# Liste des packages à vérifier
packages = [
    "numpy", "pandas", "scipy", "matplotlib", "seaborn",
    "sklearn", "statsmodels", "tables", "jupyter",
    "backtrader", "yfinance", "ta", "dash", "plotly",
    "psycopg2", "sqlalchemy", "tensorflow", "torch"
]

print(f"Python version: {sys.version}\n")

print("Vérification des packages installés:")
for package in packages:
    try:
        module = import_module(package)
        version = getattr(module, "__version__", "version inconnue")
        print(f"✅ {package} (version {version})")
    except ImportError:
        print(f"❌ {package} (non installé)")

# Vérifier CUDA pour PyTorch
if "torch" in sys.modules:
    import torch
    print("\nInformation CUDA PyTorch:")
    print(f"CUDA disponible: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"Nombre de GPUs: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            print(f"  GPU {i}: {torch.cuda.get_device_name(i)}")

# Vérifier TensorFlow
if "tensorflow" in sys.modules:
    import tensorflow as tf
    print("\nInformation CUDA TensorFlow:")
    print(f"GPUs disponibles: {tf.config.list_physical_devices('GPU')}")

print("\nEnvironnement de backtesting configuré avec succès!")
EOF

# Ajustement des permissions
chown backtester:backtester /home/backtester/test_environment.py
chmod +x /home/backtester/test_environment.py

log "Installation de l'environnement de backtesting terminée!"
log "Pour tester l'installation:"
log "  su - backtester"
log "  source ~/venv/bin/activate"
log "  python ~/test_environment.py"
log "Accédez à Jupyter Lab sur http://IP-DE-LA-VM:8888"
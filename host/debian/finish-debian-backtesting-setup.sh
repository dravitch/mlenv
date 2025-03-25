#!/bin/bash
# Script d'installation pour la VM de backtesting Debian 12
# À exécuter après l'installation du système

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
apt-get install -y build-essential gcc g++ make cmake unzip git curl wget htop nano screen tmux sudo

# Vérification de l'installation NVIDIA
log "Vérification de l'installation NVIDIA..."
nvidia-smi || log "Erreur lors de la détection GPU NVIDIA - redémarrage peut-être nécessaire"

# Installation de Python et des librairies nécessaires
log "Installation de Python et des librairies de backtesting..."
apt-get install -y python3-pip python3-dev python3-venv

# Création d'un utilisateur pour le backtesting
log "Création d'un utilisateur pour le backtesting..."
useradd -m -s /bin/bash backtester
echo "backtester:backtester" | chpasswd  # Mot de passe temporaire, à changer
usermod -aG sudo backtester

# Création d'un environnement Python dédié
su - backtester -c "python3 -m venv ~/venv"

# Installation des librairies Python pour le backtesting
su - backtester -c "
source ~/venv/bin/activate &&
pip install --upgrade pip &&
pip install numpy pandas scipy matplotlib seaborn scikit-learn statsmodels jupyterlab ipykernel ipywidgets &&
pip install pyfolio backtrader vectorbt yfinance alpha_vantage ta ccxt &&
pip install dash plotly &&
pip install psycopg2-binary SQLAlchemy &&
pip install tensorflow &&
pip install torch torchvision torchaudio
"

# Configuration de Jupyter
log "Configuration de Jupyter..."
su - backtester -c "
source ~/venv/bin/activate &&
jupyter notebook --generate-config
"

# Configuration pour accès à distance
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888clear

c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = ''  # Configuration sans mot de passe initialement
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
ufw --force enable

# Création des répertoires de projet
log "Création des répertoires de projet..."
su - backtester -c "
mkdir -p ~/projects/data
mkdir -p ~/projects/strategies
mkdir -p ~/projects/results
mkdir -p ~/projects/models
"

# Message d'installation complète
log "Installation de l'environnement de backtesting terminée!"
log "Accédez à Jupyter Lab sur http://IP-DE-LA-VM:8888"
log "Nom d'utilisateur: backtester"
log "Sécurisez Jupyter en définissant un mot de passe avec: jupyter notebook password"
log "Pour vérifier l'état des GPUs: nvidia-smi"
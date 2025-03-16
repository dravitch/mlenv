#!/bin/bash
# Script d'installation pour la VM de backtesting
# À exécuter après l'installation d'Ubuntu Server sur la VM

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC} - $1"
}

success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC} - $1"
}

warning() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC} - $1"
}

error() {
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S')${NC} - $1"
    exit 1
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root"
fi

# Paramètres (modifiables)
USER_NAME=${1:-"backtester"}
USER_PASSWORD=${2:-"backtester"}
JUPYTER_PORT=8888

log "Configuration de l'environnement de backtesting..."

# Mise à jour du système
log "Mise à jour du système..."
apt-get update && apt-get upgrade -y

# Installation des outils de base
log "Installation des outils de base..."
apt-get install -y build-essential gcc g++ make cmake unzip git curl wget htop nano screen tmux

# Installation des pilotes NVIDIA
log "Installation des pilotes NVIDIA..."
apt-get install -y software-properties-common

# Blacklister le pilote Nouveau
cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF
update-initramfs -u

# Installation des pilotes NVIDIA
log "Détection des pilotes NVIDIA appropriés..."
apt-get install -y ubuntu-drivers-common

# Détection du pilote recommandé
RECOMMENDED_DRIVER=$(ubuntu-drivers devices | grep "recommended" | awk '{print $3}')

if [ -z "$RECOMMENDED_DRIVER" ]; then
    warning "Aucun pilote NVIDIA recommandé trouvé. Installation du pilote nvidia-driver-535..."
    DRIVER_PACKAGE="nvidia-driver-535 nvidia-utils-535"
else
    log "Installation du pilote recommandé: $RECOMMENDED_DRIVER..."
    DRIVER_PACKAGE="$RECOMMENDED_DRIVER"
fi

# Installation du pilote NVIDIA
apt-get install -y $DRIVER_PACKAGE

# Installation de CUDA (optionnel, décommenter si nécessaire)
log "Voulez-vous installer CUDA? Cela peut prendre du temps mais est nécessaire pour certaines bibliothèques."
read -p "Installer CUDA? [y/N]: " install_cuda

if [[ "$install_cuda" =~ ^[Yy]$ ]]; then
    log "Installation de CUDA..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    apt-get update
    apt-get install -y cuda-toolkit-12-3

    # Configuration de l'environnement CUDA
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/profile.d/cuda.sh
    chmod +x /etc/profile.d/cuda.sh
fi

# Vérification de l'installation NVIDIA
log "Vérification de l'installation NVIDIA..."
if ! command -v nvidia-smi &> /dev/null; then
    warning "nvidia-smi non trouvé. L'installation des pilotes NVIDIA pourrait avoir échoué."
    warning "Après le redémarrage, exécutez 'nvidia-smi' pour vérifier que les GPUs sont détectés."
else
    nvidia-smi || warning "Erreur lors de la détection GPU NVIDIA - un redémarrage est nécessaire"
fi

# Installation de Python et des librairies nécessaires
log "Installation de Python et des librairies de backtesting..."
apt-get install -y python3-pip python3-dev python3-venv

# Création de l'utilisateur pour le backtesting
log "Création de l'utilisateur pour le backtesting: $USER_NAME..."
if id "$USER_NAME" &>/dev/null; then
    log "L'utilisateur $USER_NAME existe déjà."
else
    useradd -m -s /bin/bash "$USER_NAME"
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    usermod -aG sudo "$USER_NAME"
    success "Utilisateur $USER_NAME créé."
fi

# Création d'un environnement Python dédié
log "Création de l'environnement Python..."
su - "$USER_NAME" -c "python3 -m venv ~/venv"

# Installation des librairies Python pour le backtesting
log "Installation des librairies Python pour le backtesting..."
su - "$USER_NAME" -c "
source ~/venv/bin/activate &&
pip install --upgrade pip &&
pip install numpy pandas scipy matplotlib seaborn scikit-learn statsmodels pytables jupyterlab ipykernel ipywidgets &&
pip install pyfolio backtrader vectorbt yfinance alpha_vantage ta ccxt &&
pip install dash plotly &&
pip install psycopg2-binary SQLAlchemy
"

# Installation des frameworks de deep learning (optionnel)
log "Voulez-vous installer TensorFlow et PyTorch? Cela peut prendre du temps."
read -p "Installer TensorFlow et PyTorch? [y/N]: " install_dl

if [[ "$install_dl" =~ ^[Yy]$ ]]; then
    log "Installation de TensorFlow et PyTorch..."
    su - "$USER_NAME" -c "
    source ~/venv/bin/activate &&
    pip install tensorflow &&
    pip install torch torchvision torchaudio
    "
    success "TensorFlow et PyTorch installés."
fi

# Configuration de Jupyter
log "Configuration de Jupyter..."
su - "$USER_NAME" -c "
source ~/venv/bin/activate &&
jupyter notebook --generate-config
"

# Génération d'un mot de passe Jupyter sécurisé
log "Génération d'un mot de passe Jupyter sécurisé..."
JUPYTER_PASSWORD_HASH=$(su - "$USER_NAME" -c "source ~/venv/bin/activate && python3 -c \"from jupyter_server.auth import passwd; print(passwd('$USER_PASSWORD'))\"")

# Configuration pour accès à distance (avec mot de passe)
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = $JUPYTER_PORT
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = '$JUPYTER_PASSWORD_HASH'
c.NotebookApp.allow_password_change = True
EOF

# Création du service systemd pour Jupyter
log "Création du service systemd pour Jupyter..."
cat > /etc/systemd/system/jupyter.service << EOF
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=/home/$USER_NAME/venv/bin/jupyter lab --config=/etc/jupyter/jupyter_notebook_config.py
WorkingDirectory=/home/$USER_NAME
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
ufw allow $JUPYTER_PORT/tcp  # Port Jupyter
ufw allow 5432/tcp  # Port PostgreSQL (optionnel)
ufw --force enable

# Création des répertoires de projet
log "Création des répertoires de projet..."
su - "$USER_NAME" -c "
mkdir -p ~/projects/data
mkdir -p ~/projects/strategies
mkdir -p ~/projects/results
mkdir -p ~/projects/models
"

# Création d'un script de test de stratégie simple
log "Création d'un script de test de stratégie simple..."
cat > /home/$USER_NAME/projects/strategies/test_strategy.py << 'EOF'
#!/usr/bin/env python3
"""
Script de test pour une stratégie de trading simple basée sur des moyennes mobiles
"""
import pandas as pd
import numpy as np
import yfinance as yf
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

# Téléchargement des données
def download_data(symbol, period='5y'):
    data = yf.download(symbol, period=period)
    return data

# Stratégie de suivi de tendance simple
def apply_strategy(data, short_window=50, long_window=200):
    # Création des moyennes mobiles
    data['SMA_short'] = data['Close'].rolling(window=short_window).mean()
    data['SMA_long'] = data['Close'].rolling(window=long_window).mean()

    # Génération des signaux
    data['Signal'] = 0
    data['Signal'] = np.where(data['SMA_short'] > data['SMA_long'], 1, 0)
    data['Position'] = data['Signal'].diff()

    # Calcul des rendements
    data['Returns'] = data['Close'].pct_change()
    data['Strategy_Returns'] = data['Returns'] * data['Signal'].shift(1)

    # Calcul de la performance cumulative
    data['Cumulative_Returns'] = (1 + data['Returns']).cumprod()
    data['Strategy_Cumulative_Returns'] = (1 + data['Strategy_Returns']).cumprod()

    # Calcul du drawdown
    data['Peak'] = data['Strategy_Cumulative_Returns'].cummax()
    data['Drawdown'] = (data['Strategy_Cumulative_Returns'] - data['Peak']) / data['Peak']

    return data

# Fonction principale
def main():
    # Téléchargement des données
    symbol = 'SPY'
    data = download_data(symbol)

    # Application de la stratégie
    result = apply_strategy(data)

    # Calcul des métriques de performance
    total_return = result['Strategy_Cumulative_Returns'].iloc[-1] - 1
    max_drawdown = result['Drawdown'].min()
    sharpe_ratio = result['Strategy_Returns'].mean() / result['Strategy_Returns'].std() * np.sqrt(252)

    # Affichage des résultats
    print(f"Symbole: {symbol}")
    print(f"Période: {result.index[0]} à {result.index[-1]}")
    print(f"Rendement total: {total_return:.2%}")
    print(f"Drawdown maximum: {max_drawdown:.2%}")
    print(f"Ratio de Sharpe: {sharpe_ratio:.2f}")
    print(f"Ratio rendement/drawdown: {abs(total_return/max_drawdown):.2f}")

    # Sauvegarde des résultats
    result.to_csv(f"/home/$USER_NAME/projects/results/{symbol}_strategy_results.csv")

    # Visualisation
    plt.figure(figsize=(12, 8))
    plt.plot(result.index, result['Cumulative_Returns'], label='Buy & Hold')
    plt.plot(result.index, result['Strategy_Cumulative_Returns'], label='Stratégie')
    plt.title(f'Performance de la stratégie sur {symbol}')
    plt.xlabel('Date')
    plt.ylabel('Rendement cumulatif')
    plt.legend()
    plt.savefig(f"/home/$USER_NAME/projects/results/{symbol}_performance.png")

if __name__ == "__main__":
    main()
EOF

# Ajustement des permissions
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/projects
chmod +x /home/$USER_NAME/projects/strategies/test_strategy.py

# Message d'installation complète
success "Installation de l'environnement de backtesting terminée!"
log "Accédez à Jupyter Lab sur http://$(hostname -I | awk '{print $1}'):$JUPYTER_PORT"
log "Nom d'utilisateur: $USER_NAME"
log "Mot de passe: $USER_PASSWORD"
log "Le premier script de test est disponible dans ~/projects/strategies/test_strategy.py"

# Demander s'il faut redémarrer
log "Un redémarrage est recommandé pour finaliser l'installation des pilotes NVIDIA."
read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log "Redémarrage du système..."
    reboot
fi
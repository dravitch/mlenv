#!/bin/bash
# Script d'installation pour la VM de machine learning
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
USER_NAME=${1:-"aitrader"}
USER_PASSWORD=${2:-"aitrader"}
JUPYTER_PORT=8888

log "Configuration de l'environnement de machine learning..."

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

# Installation de CUDA
log "Installation de CUDA..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update
apt-get install -y cuda-toolkit-12-3

# Installation de cuDNN
log "Voulez-vous installer cuDNN? C'est recommandé pour les performances de deep learning."
read -p "Installer cuDNN? [y/N]: " install_cudnn

if [[ "$install_cudnn" =~ ^[Yy]$ ]]; then
    log "Installation de cuDNN..."
    apt-get install -y libcudnn8 libcudnn8-dev
fi

# Configuration de l'environnement CUDA
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/profile.d/cuda.sh
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/profile.d/cuda.sh
chmod +x /etc/profile.d/cuda.sh

# Vérification de l'installation NVIDIA
log "Vérification de l'installation NVIDIA..."
if ! command -v nvidia-smi &> /dev/null; then
    warning "nvidia-smi non trouvé. L'installation des pilotes NVIDIA pourrait avoir échoué."
    warning "Après le redémarrage, exécutez 'nvidia-smi' pour vérifier que les GPUs sont détectés."
else
    nvidia-smi || warning "Erreur lors de la détection GPU NVIDIA - un redémarrage est nécessaire"
fi

# Installation de Python et des librairies nécessaires
log "Installation de Python et des librairies de ML..."
apt-get install -y python3-pip python3-dev python3-venv

# Création de l'utilisateur pour le ML
log "Création de l'utilisateur pour le machine learning: $USER_NAME..."
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

# Installation des librairies Python communes
log "Installation des librairies Python communes..."
su - "$USER_NAME" -c "
source ~/venv/bin/activate &&
pip install --upgrade pip &&
pip install numpy pandas scipy matplotlib seaborn scikit-learn statsmodels pytables jupyterlab ipykernel ipywidgets &&
pip install pyfolio yfinance alpha_vantage ta ccxt &&
pip install dash plotly &&
pip install psycopg2-binary SQLAlchemy
"

# Installation des frameworks de deep learning
log "Installation des frameworks de deep learning..."
su - "$USER_NAME" -c "
source ~/venv/bin/activate &&
pip install tensorflow==2.14.0 tensorflow-gpu==2.14.0 &&
pip install torch torchvision torchaudio &&
pip install transformers huggingface-hub &&
pip install xgboost lightgbm catboost &&
pip install optuna hyperopt &&
pip install ray[tune] &&
pip install gym stable-baselines3 &&
pip install gpflow bayesian-optimization
"

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
ufw allow 8787/tcp  # Port pour service API
ufw --force enable

# Création des répertoires de projet
log "Création des répertoires de projet..."
su - "$USER_NAME" -c "
mkdir -p ~/projects/data
mkdir -p ~/projects/models
mkdir -p ~/projects/results
mkdir -p ~/projects/agents
mkdir -p ~/projects/api
"

# Création d'un script de test des GPUs
log "Création d'un script de test des GPUs..."
cat > /home/$USER_NAME/projects/test_gpu.py << 'EOF'
#!/usr/bin/env python3
"""
Script de test pour vérifier l'utilisation des GPUs
"""
import tensorflow as tf
import torch
import time
import os

def test_tensorflow():
    print("======= Test TensorFlow =======")
    print(f"TensorFlow version: {tf.__version__}")
    print(f"Num GPUs Available: {len(tf.config.list_physical_devices('GPU'))}")

    gpus = tf.config.list_physical_devices('GPU')
    if gpus:
        for gpu in gpus:
            print(f"GPU found: {gpu}")

        # Création d'un simple modèle pour tester la disponibilité des GPUs
        print("Exécution d'un test de performance sur GPU...")

        # Créer des données de test
        x = tf.random.normal([5000, 5000])

        # Mesurer le temps pour une opération matricielle
        start_time = time.time()
        result = tf.matmul(x, x)
        elapsed_time = time.time() - start_time

        print(f"Multiplication matricielle sur GPU terminée en {elapsed_time:.2f} secondes")
    else:
        print("Aucun GPU trouvé pour TensorFlow!")

def test_pytorch():
    print("\n======= Test PyTorch =======")
    print(f"PyTorch version: {torch.__version__}")
    print(f"CUDA available: {torch.cuda.is_available()}")

    if torch.cuda.is_available():
        num_gpus = torch.cuda.device_count()
        print(f"Nombre de GPUs disponibles: {num_gpus}")

        for i in range(num_gpus):
            print(f"GPU {i}: {torch.cuda.get_device_name(i)}")

        # Test de performance
        print("Exécution d'un test de performance sur GPU...")

        # Création de tenseurs aléatoires sur GPU
        x = torch.randn(5000, 5000, device="cuda")
        y = torch.randn(5000, 5000, device="cuda")

        # Mesurer le temps pour une opération matricielle
        start_time = time.time()
        result = torch.matmul(x, y)
        # Synchronisation pour assurer que le calcul est terminé
        torch.cuda.synchronize()
        elapsed_time = time.time() - start_time

        print(f"Multiplication matricielle sur GPU terminée en {elapsed_time:.2f} secondes")
    else:
        print("Aucun GPU trouvé pour PyTorch!")

if __name__ == "__main__":
    print("Test de détection et performance des GPUs...")
    test_tensorflow()
    test_pytorch()
    print("\nTest terminé!")
EOF

# Création d'un exemple d'agent de trading RL simplifié
log "Création d'un exemple d'agent de trading RL..."
cat > /home/$USER_NAME/projects/agents/rl_trading_agent.py << 'EOF'
#!/usr/bin/env python3
"""
Agent de trading simplifié basé sur l'apprentissage par renforcement (RL)
Exemple simple utilisant Stable Baselines3
"""
import numpy as np
import pandas as pd
import gym
from gym import spaces
import matplotlib.pyplot as plt
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
import yfinance as yf

# Définition d'un environnement de trading simplifié
class TradingEnv(gym.Env):
    """Environnement de trading pour RL"""
    metadata = {'render.modes': ['human']}

    def __init__(self, df, initial_balance=10000, commission=0.001):
        super(TradingEnv, self).__init__()
        self.df = df
        self.initial_balance = initial_balance
        self.commission = commission

        # Commencer avec un historique suffisant pour calculer les features
        self.current_step = 30

        # Espace d'observation: 5 features + position + solde
        self.observation_space = spaces.Box(low=-np.inf, high=np.inf, shape=(7,), dtype=np.float32)

        # Actions: 0=Vendre, 1=Tenir, 2=Acheter
        self.action_space = spaces.Discrete(3)

        # Reset initial
        self.reset()

    def reset(self):
        self.current_step = 30
        self.balance = self.initial_balance
        self.shares_held = 0
        self.net_worth_history = [self.initial_balance]
        return self._next_observation()

    def _calculate_features(self):
        # Calcul de features simples
        data = self.df.iloc[:self.current_step].copy()

        # Rendements sur différentes périodes
        data['returns_1d'] = data['Close'].pct_change(1)
        data['returns_5d'] = data['Close'].pct_change(5)

        # Moyennes mobiles
        data['sma_10'] = data['Close'].rolling(window=10).mean()
        data['sma_30'] = data['Close'].rolling(window=30).mean()

        # Volatilité
        data['volatility'] = data['returns_1d'].rolling(window=10).std()

        # Features actuelles
        current = data.iloc[-1]
        features = np.array([
            current['returns_1d'],
            current['returns_5d'],
            current['Close'] / current['sma_10'] - 1,  # Position relative à la SMA10
            current['Close'] / current['sma_30'] - 1,  # Position relative à la SMA30
            current['volatility']
        ])
        return features

    def _next_observation(self):
        # Construction de l'observation complète
        features = self._calculate_features()

        # Prix actuel et information du portefeuille
        current_price = self.df.iloc[self.current_step]['Close']
        portfolio_info = np.array([
            self.shares_held * current_price / self.initial_balance,  # Position relative
            self.balance / self.initial_balance  # Solde relatif
        ])

        # Combinaison des features
        observation = np.append(features, portfolio_info)
        return observation

    def step(self, action):
        # Exécuter une action et passer à l'étape suivante
        self.current_step += 1
        current_price = self.df.iloc[self.current_step]['Close']

        # Action: 0=Vendre, 1=Tenir, 2=Acheter
        if action == 0 and self.shares_held > 0:  # Vendre
            # Vendre toutes les actions
            self.balance += self.shares_held * current_price * (1 - self.commission)
            self.shares_held = 0
        elif action == 2 and self.balance > current_price:  # Acheter
            # Calculer le nombre d'actions à acheter (max 20% du solde)
            affordable_shares = int((self.balance * 0.2) / current_price)
            if affordable_shares > 0:
                self.shares_held += affordable_shares
                self.balance -= affordable_shares * current_price * (1 + self.commission)

        # Calculer la valeur nette
        net_worth = self.balance + self.shares_held * current_price
        self.net_worth_history.append(net_worth)

        # Calculer la récompense (rendement relatif)
        reward = (net_worth / self.net_worth_history[-2]) - 1

        # Vérifier si l'épisode est terminé
        done = self.current_step >= len(self.df) - 1

        return self._next_observation(), reward, done, {}

    def render(self, mode='human'):
        profit = self.net_worth_history[-1] - self.initial_balance
        print(f'Étape: {self.current_step}')
        print(f'Solde: {self.balance:.2f}')
        print(f'Actions: {self.shares_held}')
        print(f'Valeur nette: {self.net_worth_history[-1]:.2f}')
        print(f'Profit: {profit:.2f} ({profit/self.initial_balance:.2%})')
        return self.net_worth_history

# Fonction pour télécharger des données
def download_data(symbol='SPY', period='2y'):
    """Télécharge les données historiques."""
    data = yf.download(symbol, period=period)
    return data

# Fonction d'entraînement
def train_model(symbol='SPY', timesteps=10000):
    """Entraîne un agent RL sur les données de marché."""
    # Télécharger les données
    df = download_data(symbol)

    # Créer l'environnement
    env = TradingEnv(df)
    env = DummyVecEnv([lambda: env])

    # Créer et entraîner le modèle
    model = PPO('MlpPolicy', env, verbose=1)
    model.learn(total_timesteps=timesteps)

    return model, df

# Fonction de test
def test_model(model, df):
    """Teste un modèle entraîné."""
    env = TradingEnv(df)
    obs = env.reset()
    done = False

    while not done:
        action, _states = model.predict(obs)
        obs, reward, done, info = env.step(action)

    # Afficher les résultats
    history = env.render()

    # Tracer la valeur nette au fil du temps
    plt.figure(figsize=(10, 6))
    plt.plot(history)
    plt.title('Performance de l\'agent RL')
    plt.xlabel('Jours')
    plt.ylabel('Valeur du portefeuille ($)')
    plt.grid(True)
    plt.savefig('rl_performance.png')
    plt.show()

    return history

# Point d'entrée principal
if __name__ == "__main__":
    print("Cet exemple montre comment créer un agent de trading RL simple.")
    print("Pour exécuter l'entraînement:")
    print("  model, data = train_model('AAPL', timesteps=5000)")
    print("  history = test_model(model, data)")
EOF

# Ajustement des permissions
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/projects
chmod +x /home/$USER_NAME/projects/test_gpu.py
chmod +x /home/$USER_NAME/projects/agents/rl_trading_agent.py

# Message d'installation complète
success "Installation de l'environnement de machine learning terminée!"
log "Accédez à Jupyter Lab sur http://$(hostname -I | awk '{print $1}'):$JUPYTER_PORT"
log "Nom d'utilisateur: $USER_NAME"
log "Mot de passe: $USER_PASSWORD"
log "Pour vérifier l'état des GPUs, exécutez: python3 ~/projects/test_gpu.py"

# Demander s'il faut redémarrer
log "Un redémarrage est recommandé pour finaliser l'installation des pilotes NVIDIA."
read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log "Redémarrage du système..."
    reboot
fi
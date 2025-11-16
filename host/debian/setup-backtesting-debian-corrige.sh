#!/bin/bash
# Script pour finaliser l'installation de Jupyter et configurer le service
# À exécuter après l'installation de l'environnement Python et CUDA

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

# Vérifier que l'environnement virtuel existe
if [ ! -d "/home/backtester/venv" ]; then
    log "L'environnement virtuel de backtester n'existe pas. Création..."
    su - backtester -c "python3 -m venv ~/venv"
fi

# Installer ou mettre à jour Jupyter si nécessaire
log "Installation/mise à jour de Jupyter dans l'environnement virtuel..."
su - backtester -c "source ~/venv/bin/activate && pip install --upgrade jupyterlab jupyter_core jupyter_client notebook ipykernel ipywidgets"

# Générer une configuration Jupyter si elle n'existe pas
if [ ! -f "/home/backtester/.jupyter/jupyter_notebook_config.py" ]; then
    log "Génération de la configuration Jupyter pour l'utilisateur backtester..."
    su - backtester -c "source ~/venv/bin/activate && jupyter notebook --generate-config"
fi

# Configuration de Jupyter
log "Configuration de Jupyter..."
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Par défaut, pas de mot de passe
# Pour définir un mot de passe, exécutez :
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
# et remplacez la valeur ci-dessous
c.NotebookApp.password = ''
EOF

# Création d'un service systemd pour Jupyter
log "Création du service systemd pour Jupyter..."
cat > /etc/systemd/system/jupyter.service << EOF
[Unit]
Description=Jupyter Lab Server
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

# Recharger systemd
log "Rechargement de systemd..."
systemctl daemon-reload

# Activation et démarrage du service
log "Activation et démarrage du service Jupyter..."
systemctl enable jupyter.service
systemctl start jupyter.service

# Vérification du statut du service
log "Vérification du statut du service Jupyter..."
#systemctl status jupyter.service

# Création d'un notebook de test
log "Création d'un notebook de test..."
TEST_NOTEBOOK_DIR="/home/backtester/notebooks"
su - backtester -c "mkdir -p $TEST_NOTEBOOK_DIR"

cat > /tmp/test_notebook.py << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Test de l'environnement de backtesting\n",
    "\n",
    "Ce notebook vérifie si votre environnement est correctement configuré."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "source": [
    "import sys\n",
    "print(f\"Python version: {sys.version}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "source": [
    "# Vérification des packages essentiels\n",
    "packages_to_check = [\n",
    "    \"numpy\", \"pandas\", \"matplotlib\", \"seaborn\", \n",
    "    \"sklearn\", \"torch\", \"tensorflow\"\n",
    "]\n",
    "\n",
    "for package in packages_to_check:\n",
    "    try:\n",
    "        module = __import__(package)\n",
    "        version = getattr(module, \"__version__\", \"version inconnue\")\n",
    "        print(f\"✅ {package} (version {version})\")\n",
    "    except ImportError:\n",
    "        print(f\"❌ {package} (non installé)\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "source": [
    "# Vérification de CUDA pour PyTorch\n",
    "try:\n",
    "    import torch\n",
    "    print(f\"CUDA disponible: {torch.cuda.is_available()}\")\n",
    "    if torch.cuda.is_available():\n",
    "        print(f\"Nombre de GPUs: {torch.cuda.device_count()}\")\n",
    "        for i in range(torch.cuda.device_count()):\n",
    "            print(f\"  GPU {i}: {torch.cuda.get_device_name(i)}\")\n",
    "except ImportError:\n",
    "    print(\"PyTorch n'est pas installé.\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.8.10"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

# Convertir le fichier Python en notebook Jupyter
su - backtester -c "mkdir -p $TEST_NOTEBOOK_DIR"
mv /tmp/test_notebook.py "$TEST_NOTEBOOK_DIR/test_environment.ipynb"
chown backtester:backtester "$TEST_NOTEBOOK_DIR/test_environment.ipynb"

# Ouvrir les ports du pare-feu si ufw est activé
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    log "Configuration du pare-feu pour Jupyter..."
    ufw allow 8888/tcp comment "Jupyter Lab"
fi

# Affichage des informations finales
IP_ADDRESS=$(hostname -I | awk '{print $1}')
log "Installation de Jupyter terminée!"
log "Accédez à Jupyter Lab via: http://$IP_ADDRESS:8888"
log "Les notebooks se trouvent dans: $TEST_NOTEBOOK_DIR"
log "Pour définir un mot de passe pour Jupyter, exécutez :"
log "  su - backtester"
log "  source ~/venv/bin/activate"
log "  python -c \"from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))\""
log "Puis modifiez la valeur de c.NotebookApp.password dans /etc/jupyter/jupyter_notebook_config.py"
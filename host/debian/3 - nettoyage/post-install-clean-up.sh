#!/bin/bash
# Script de nettoyage post-installation pour VM de backtesting
# À exécuter après l'installation des composants essentiels

set -e

echo "Démarrage du nettoyage post-installation..."

# 1. Nettoyer les caches apt
echo "Nettoyage des caches apt..."
apt clean
apt autoremove -y

# 2. Supprimer les fichiers temporaires
echo "Suppression des fichiers temporaires..."
rm -rf /var/cache/apt/archives/*.deb
rm -rf /tmp/*
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
journalctl --vacuum-time=1d

# 3. Nettoyer CUDA
echo "Nettoyage des composants CUDA non essentiels..."
if [ -d "/usr/local/cuda" ]; then
    du -sh /usr/local/cuda/doc /usr/local/cuda/samples /usr/local/cuda/extras /usr/local/cuda/nsightee_plugins 2>/dev/null || true

    # Supprimer la documentation
    rm -rf /usr/local/cuda/doc

    # Supprimer les exemples
    rm -rf /usr/local/cuda/samples

    # Supprimer les extras
    rm -rf /usr/local/cuda/extras

    # Supprimer les outils Nsight si non nécessaires
    rm -rf /usr/local/cuda/nsightee_plugins
    rm -rf /usr/local/cuda/libnvvp

    # Supprimer les outils de développement si non nécessaires
    rm -rf /usr/local/cuda/nsight-compute-*
    rm -rf /usr/local/cuda/compute-sanitizer

    echo "Espace disque après nettoyage CUDA:"
    du -sh /usr/local/cuda
fi

# 4. Nettoyer l'environnement Python si présent
if [ -d "/home/backtester/venv" ]; then
    echo "Nettoyage des caches Python..."
    find /home/backtester/venv -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find /home/backtester/venv -name "*.pyc" -delete
    find /home/backtester -name ".cache" -type d -exec rm -rf {} + 2>/dev/null || true
fi

# 5. Supprimer les outils de compilation si plus nécessaires (optionnel - commentez si besoin)
# echo "Suppression des outils de compilation (commentez cette section si vous en avez encore besoin)..."
# apt remove --purge -y build-essential gcc g++ make cmake
# apt autoremove -y

# 6. Afficher l'espace disque final
echo "Nettoyage terminé. Espace disque actuel:"
df -h /

echo "Liste des plus gros répertoires:"
du -h --max-depth=2 / | sort -hr | head -10

echo "Nettoyage post-installation terminé avec succès."
#!/bin/bash
# clean-disk-space.sh - Script de nettoyage d'espace disque pour VM de backtesting/ML
# À exécuter en tant que root après installation quand l'espace disque est faible

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root" >&2
    exit 1
fi

# Affichage de l'espace disque avant nettoyage
log "Espace disque avant nettoyage:"
df -h /

# 1. Nettoyer les caches apt
log "Nettoyage des caches apt..."
apt clean
apt autoremove -y

# 2. Supprimer les fichiers temporaires
log "Suppression des fichiers temporaires..."
rm -rf /var/cache/apt/archives/*.deb
rm -rf /tmp/*
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
find /var/log -type f -name "*.[0-9]" -delete

# 3. Nettoyer les journaux
log "Nettoyage des journaux..."
journalctl --vacuum-time=1d

# 4. Nettoyer CUDA
if [ -d "/usr/local/cuda" ]; then
    log "Nettoyage des composants CUDA non essentiels..."

    # Afficher la taille avant nettoyage
    log "Taille de CUDA avant nettoyage:"
    du -sh /usr/local/cuda

    # Supprimer la documentation (économiser ~1GB)
    if [ -d "/usr/local/cuda/doc" ]; then
        du -sh /usr/local/cuda/docs
        rm -rf /usr/local/cuda/docs
        success "Documentation CUDA supprimée"
    fi

    # Supprimer les exemples (économiser ~2GB)
    if [ -d "/usr/local/cuda/samples" ]; then
        du -sh /usr/local/cuda/samples
        rm -rf /usr/local/cuda/samples
        success "Exemples CUDA supprimés"
    fi

    # Supprimer les extras (économiser ~100MB)
    if [ -d "/usr/local/cuda/extras" ]; then
        du -sh /usr/local/cuda/extras
        rm -rf /usr/local/cuda/extras
        success "Extras CUDA supprimés"
    fi

    # Supprimer les outils Nsight si non nécessaires (économiser ~200MB)
    if [ -d "/usr/local/cuda/nsightee_plugins" ]; then
        du -sh /usr/local/cuda/nsightee_plugins
        rm -rf /usr/local/cuda/nsightee_plugins
        success "Plugins Nsight supprimés"
    fi

    if [ -d "/usr/local/cuda/libnvvp" ]; then
        du -sh /usr/local/cuda/libnvvp
        rm -rf /usr/local/cuda/libnvvp
        success "libnvvp supprimé"
    fi

    # Supprimer les outils de développement si non nécessaires (économiser ~500MB)
    if [ -d "/usr/local/cuda/nsight-compute-"* ]; then
        du -sh /usr/local/cuda/nsight-compute-*
        rm -rf /usr/local/cuda/nsight-compute-*
        success "Nsight Compute supprimé"
    fi

    if [ -d "/usr/local/cuda/compute-sanitizer" ]; then
        du -sh /usr/local/cuda/compute-sanitizer
        rm -rf /usr/local/cuda/compute-sanitizer
        success "Compute Sanitizer supprimé"
    fi

    # Afficher la taille après nettoyage
    log "Taille de CUDA après nettoyage:"
    du -sh /usr/local/cuda
fi

# 5. Nettoyer l'environnement Python
if [ -d "/home/backtester/venv" ]; then
    log "Nettoyage des caches Python..."
    find /home/backtester/venv -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find /home/backtester/venv -name "*.pyc" -delete
    find /home/backtester -name ".cache" -type d -exec rm -rf {} + 2>/dev/null || true
    success "Caches Python nettoyés"
fi

# 6. Nettoyer pip cache
if [ -d "/root/.cache/pip" ]; then
    log "Nettoyage du cache pip root..."
    rm -rf /root/.cache/pip
    success "Cache pip root nettoyé"
fi

if [ -d "/home/backtester/.cache/pip" ]; then
    log "Nettoyage du cache pip utilisateur..."
    rm -rf /home/backtester/.cache/pip
    success "Cache pip utilisateur nettoyé"
fi

# 7. Nettoyer les anciennes versions du noyau Linux
log "Nettoyage des anciens noyaux Linux..."
apt autoremove --purge -y

# 8. Nettoyer les archives des packages
log "Nettoyage des archives de packages..."
apt-get clean

# 9. Vider la corbeille
if [ -d "/home/backtester/.local/share/Trash" ]; then
    log "Vidage de la corbeille utilisateur..."
    rm -rf /home/backtester/.local/share/Trash/*
    success "Corbeille vidée"
fi

# Afficher l'espace disque après nettoyage
log "Espace disque après nettoyage:"
df -h /

log "Les répertoires les plus volumineux restants:"
du -h --max-depth=1 / | sort -hr | head -10

log "Nettoyage terminé avec succès!"
echo "Si vous avez encore besoin d'espace disque supplémentaire, considérez les actions suivantes:"
echo "1. Supprimer les données de projets non utilisées (/home/backtester/projects)"
echo "2. Supprimer/déplacer les téléchargements anciens (/home/backtester/Downloads)"
echo "3. Utiliser 'apt autoremove --purge -y' pour supprimer plus de packages non utilisés"
echo "4. Envisager de redimensionner votre partition principale si possible"
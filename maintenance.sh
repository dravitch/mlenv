#!/bin/bash
# Script de maintenance pour Proxmox VE
# Exécuter régulièrement pour maintenir la santé du système
# Recommandé: ajouter au crontab hebdomadaire

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
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root"
    exit 1
fi

# Création du répertoire de logs
LOG_DIR="/var/log/maintenance"
LOG_FILE="$LOG_DIR/maintenance-$(date +%Y%m%d).log"
mkdir -p "$LOG_DIR"

# Fonction pour écrire dans le fichier de log
log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Introduction
log "Démarrage de la maintenance du système..."
log_to_file "Démarrage de la maintenance du système"

# 1. Nettoyage des journaux système
log "1. Nettoyage des journaux système..."
log_to_file "Nettoyage des journaux système"

# Compression et suppression des anciens journaux
find /var/log -type f -name "*.gz" -mtime +30 -delete
find /var/log -type f -name "*.[0-9]" -mtime +7 -delete
success "Anciens journaux compressés supprimés"

# Nettoyage des journaux systemd
log "Nettoyage des journaux systemd..."
journalctl --vacuum-time=7d > /dev/null 2>&1
success "Journaux systemd nettoyés"
log_to_file "Journaux systemd nettoyés - conservés 7 derniers jours"

# 2. Nettoyage des paquets
log "2. Nettoyage des paquets..."
log_to_file "Nettoyage des paquets"

# Nettoyage du cache APT
apt-get clean
apt-get autoclean
success "Cache APT nettoyé"
log_to_file "Cache APT nettoyé"

# Suppression des paquets obsolètes
log "Suppression des paquets obsolètes..."
apt-get autoremove -y
success "Paquets obsolètes supprimés"
log_to_file "Paquets obsolètes supprimés"

# 3. Vérification de l'espace disque
log "3. Vérification de l'espace disque..."
log_to_file "Vérification de l'espace disque"

# Affichage de l'utilisation du disque
df -h | grep -v tmpfs | grep -v loop
log_to_file "$(df -h | grep -v tmpfs | grep -v loop)"

# Vérification de l'espace disque critique
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$ROOT_USAGE" -gt 85 ]; then
    warning "ALERTE: L'espace disque sur / est critique: $ROOT_USAGE%"
    log_to_file "ALERTE: L'espace disque sur / est critique: $ROOT_USAGE%"

    # Identifier les répertoires volumineux
    log "Répertoires les plus volumineux dans /var:"
    du -h --max-depth=2 /var | sort -hr | head -10
    log_to_file "Répertoires les plus volumineux dans /var:"
    log_to_file "$(du -h --max-depth=2 /var | sort -hr | head -10)"
else
    success "Espace disque OK: $ROOT_USAGE%"
    log_to_file "Espace disque OK: $ROOT_USAGE%"
fi

# 4. Nettoyage du stockage Proxmox
log "4. Nettoyage du stockage Proxmox..."
log_to_file "Nettoyage du stockage Proxmox"

# Nettoyage du répertoire temporaire
rm -rf /var/tmp/vzdump* 2>/dev/null || true
success "Fichiers temporaires de sauvegarde supprimés"

# Conservation uniquement des 5 dernières sauvegardes par VM
BACKUP_DIR="/mnt/vmstorage/backups"

if [ -d "$BACKUP_DIR" ]; then
    log "Nettoyage des anciennes sauvegardes..."

    # Identification des VMs et conteneurs avec sauvegardes
    VM_LIST=$(find "$BACKUP_DIR" -name "vzdump-qemu-*" | sed -E 's/.*vzdump-qemu-([0-9]+)-[0-9_]+.*/\1/g' | sort -u)
    CT_LIST=$(find "$BACKUP_DIR" -name "vzdump-lxc-*" | sed -E 's/.*vzdump-lxc-([0-9]+)-[0-9_]+.*/\1/g' | sort -u)

    # Nettoyage des sauvegardes de VMs
    for vm in $VM_LIST; do
        BACKUP_COUNT=$(find "$BACKUP_DIR" -name "vzdump-qemu-$vm-*" | wc -l)
        if [ "$BACKUP_COUNT" -gt 5 ]; then
            log "VM $vm: $BACKUP_COUNT sauvegardes trouvées, conservation des 5 plus récentes"
            find "$BACKUP_DIR" -name "vzdump-qemu-$vm-*" | sort | head -n -5 | xargs rm -f
            log_to_file "Nettoyage des sauvegardes pour VM $vm: conservé 5/$BACKUP_COUNT"
        fi
    done

    # Nettoyage des sauvegardes de conteneurs
    for ct in $CT_LIST; do
        BACKUP_COUNT=$(find "$BACKUP_DIR" -name "vzdump-lxc-$ct-*" | wc -l)
        if [ "$BACKUP_COUNT" -gt 5 ]; then
            log "Conteneur $ct: $BACKUP_COUNT sauvegardes trouvées, conservation des 5 plus récentes"
            find "$BACKUP_DIR" -name "vzdump-lxc-$ct-*" | sort | head -n -5 | xargs rm -f
            log_to_file "Nettoyage des sauvegardes pour CT $ct: conservé 5/$BACKUP_COUNT"
        fi
    done

    success "Nettoyage des sauvegardes terminé"
else
    log "Répertoire de sauvegarde $BACKUP_DIR non trouvé, ignoré"
    log_to_file "Répertoire de sauvegarde $BACKUP_DIR non trouvé, ignoré"
fi

# 5. Vérification des mises à jour disponibles
log "5. Vérification des mises à jour disponibles..."
log_to_file "Vérification des mises à jour disponibles"

# Mise à jour des listes de paquets
apt-get update

# Liste des mises à jour disponibles
UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
if [ "$UPDATES" -gt 0 ]; then
    log "Il y a $UPDATES mises à jour disponibles:"
    apt list --upgradable 2>/dev/null | grep -v "Listing..."
    log_to_file "Il y a $UPDATES mises à jour disponibles"
else
    success "Le système est à jour"
    log_to_file "Le système est à jour"
fi

# 6. Vérification de l'état des VMs et conteneurs
log "6. Vérification de l'état des VMs et conteneurs..."
log_to_file "Vérification de l'état des VMs et conteneurs"

# Liste des VMs
VM_STATUS=$(qm list)
log "État des VMs:"
echo "$VM_STATUS"
log_to_file "État des VMs:"
log_to_file "$VM_STATUS"

# Liste des conteneurs
CT_STATUS=$(pct list)
log "État des conteneurs:"
echo "$CT_STATUS"
log_to_file "État des conteneurs:"
log_to_file "$CT_STATUS"

# 7. Vérification de l'état du GPU
log "7. Vérification de l'état du GPU..."
log_to_file "Vérification de l'état du GPU"

# Vérifier les modules VFIO
VFIO_MODULES=$(lsmod | grep vfio)
if [ -n "$VFIO_MODULES" ]; then
    log "Modules VFIO chargés:"
    echo "$VFIO_MODULES"
    log_to_file "Modules VFIO chargés"
else
    warning "Aucun module VFIO chargé. Le passthrough GPU pourrait ne pas fonctionner."
    log_to_file "ALERTE: Aucun module VFIO chargé"
fi

# Vérifier les groupes IOMMU
log "Groupes IOMMU pour les GPU NVIDIA:"
IOMMU_GROUPS=$(find /sys/kernel/iommu_groups/ -type l | sort -V | while read -r iommu; do
    GROUP=$(basename "$(dirname "$iommu")")
    DEVICE=$(basename "$iommu")
    DEVICE_INFO=$(lspci -s "$DEVICE" | grep -i nvidia)
    if [ -n "$DEVICE_INFO" ]; then
        echo "Groupe $GROUP: $DEVICE_INFO"
    fi
done)

if [ -n "$IOMMU_GROUPS" ]; then
    echo "$IOMMU_GROUPS"
    log_to_file "Groupes IOMMU pour les GPU NVIDIA trouvés"
else
    warning "Aucun GPU NVIDIA trouvé dans les groupes IOMMU."
    log_to_file "ALERTE: Aucun GPU NVIDIA trouvé dans les groupes IOMMU"
fi

# 8. Conservation des logs de maintenance
log "8. Nettoyage des anciens logs de maintenance..."
find "$LOG_DIR" -name "maintenance-*.log" -mtime +30 -delete
success "Anciens logs de maintenance supprimés (>30 jours)"

# Résumé
success "Maintenance du système terminée avec succès!"
log_to_file "Maintenance du système terminée avec succès"

# Afficher un résumé des éléments vérifiés
echo
echo -e "${GREEN}=== Résumé de la maintenance ===${NC}"
echo -e "✅ Nettoyage des journaux système"
echo -e "✅ Nettoyage des paquets"
echo -e "✅ Vérification de l'espace disque (${ROOT_USAGE}%)"
echo -e "✅ Nettoyage du stockage Proxmox"
echo -e "✅ Vérification des mises à jour ($UPDATES disponibles)"
echo -e "✅ Vérification des VMs et conteneurs"
echo -e "✅ Vérification de l'état du GPU"
echo

log "Log de maintenance enregistré dans: $LOG_FILE"
#!/bin/bash
# Script de configuration du disque M.2 pour Proxmox VE
# À exécuter sur l'hôte Proxmox après l'installation de base

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

# Vérifier si le point de montage existe déjà
STORAGE_PATH=${1:-"/mnt/vmstorage"}

if [ -d "$STORAGE_PATH" ] && mountpoint -q "$STORAGE_PATH"; then
    warning "Le répertoire $STORAGE_PATH est déjà monté. Configuration ignorée."
    exit 0
fi

# Détection automatique du disque M.2
log "Détection des disques M.2 disponibles..."
NVME_DISKS=$(lsblk -d -n -p -o NAME | grep -i nvme)

if [ -z "$NVME_DISKS" ]; then
    warning "Aucun disque NVMe détecté. Recherche de disques SSD..."
    SSD_DISKS=$(lsblk -d -n -p -o NAME,ROTA | grep '0$' | awk '{print $1}')

    if [ -z "$SSD_DISKS" ]; then
        error "Aucun disque NVMe ou SSD détecté. Impossible de configurer le stockage M.2."
    else
        log "Disques SSD détectés:"
        echo "$SSD_DISKS"

        # Sélectionner le premier SSD comme disque par défaut
        M2_DISK=$(echo "$SSD_DISKS" | head -n 1)
    fi
else
    log "Disques NVMe détectés:"
    echo "$NVME_DISKS"

    # Sélectionner le premier NVMe comme disque par défaut
    M2_DISK=$(echo "$NVME_DISKS" | head -n 1)
fi

# Demander confirmation à l'utilisateur
log "Disque sélectionné pour le stockage: $M2_DISK"
echo -e "${YELLOW}ATTENTION: Ce disque sera formaté et toutes les données seront perdues!${NC}"
read -p "Voulez-vous utiliser $M2_DISK pour le stockage Proxmox? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    # Si l'utilisateur n'a pas confirmé, proposer la sélection manuelle
    read -p "Veuillez entrer le chemin complet du disque à utiliser (ex: /dev/nvme0n1): " M2_DISK

    if [ -z "$M2_DISK" ] || [ ! -b "$M2_DISK" ]; then
        error "Disque invalide ou inexistant: $M2_DISK"
    fi

    log "Disque sélectionné manuellement: $M2_DISK"
    echo -e "${YELLOW}ATTENTION: Ce disque sera formaté et toutes les données seront perdues!${NC}"
    read -p "Confirmez-vous l'utilisation de $M2_DISK? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Configuration annulée par l'utilisateur."
    fi
fi

# Détecter si le disque est déjà partitionné
PARTITIONS=$(lsblk -n -p -o NAME "$M2_DISK" | grep -v "^$M2_DISK$")

if [ -n "$PARTITIONS" ]; then
    log "Partitions existantes détectées sur $M2_DISK:"
    echo "$PARTITIONS"
    read -p "Voulez-vous supprimer toutes les partitions existantes? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Configuration annulée par l'utilisateur."
    fi

    log "Suppression des partitions existantes..."
    # Détacher toutes les partitions qui pourraient être montées
    for part in $PARTITIONS; do
        if mountpoint -q "$part"; then
            umount "$part"
        fi
    done

    # Effacer la table de partitions
    sgdisk --zap-all "$M2_DISK"
    partprobe "$M2_DISK"
    sleep 2
fi

# Choisir le système de fichiers à utiliser
log "Choisissez le système de fichiers à utiliser:"
echo "1) ext4 (recommandé pour compatibilité générale)"
echo "2) xfs (performances meilleures pour gros fichiers)"
echo "3) zfs (avancé, snapshots et compression)"
read -p "Votre choix [1-3]: " fs_choice

case $fs_choice in
    1)
        FS_TYPE="ext4"
        ;;
    2)
        FS_TYPE="xfs"
        ;;
    3)
        FS_TYPE="zfs"
        ;;
    *)
        log "Choix invalide. Utilisation d'ext4 par défaut."
        FS_TYPE="ext4"
        ;;
esac

# Créer le point de montage
log "Création du point de montage $STORAGE_PATH..."
mkdir -p "$STORAGE_PATH"

# Configuration en fonction du système de fichiers choisi
if [ "$FS_TYPE" = "zfs" ]; then
    # Vérifier si ZFS est installé
    if ! command -v zpool &> /dev/null; then
        log "Installation de ZFS..."
        apt-get update && apt-get install -y zfsutils-linux
    fi

    # Créer le pool ZFS
    log "Création du pool ZFS..."
    POOL_NAME="vmstorage"

    # Vérifier si le pool existe déjà
    if zpool list | grep -q "$POOL_NAME"; then
        warning "Le pool ZFS '$POOL_NAME' existe déjà."
        read -p "Voulez-vous le détruire et le recréer? [y/N]: " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            log "Destruction du pool ZFS existant..."
            zpool destroy "$POOL_NAME"
        else
            error "Configuration annulée. Utilisez le pool ZFS existant."
        fi
    fi

    # Créer le pool ZFS
    zpool create -f -o ashift=12 "$POOL_NAME" "$M2_DISK"

    # Créer les systèmes de fichiers ZFS
    log "Création des systèmes de fichiers ZFS..."
    zfs create "$POOL_NAME/images"
    zfs create "$POOL_NAME/containers"
    zfs create "$POOL_NAME/backups"
    zfs create "$POOL_NAME/iso"

    # Configurer les propriétés ZFS pour de meilleures performances
    log "Configuration des propriétés ZFS..."
    zfs set compression=lz4 "$POOL_NAME"
    zfs set atime=off "$POOL_NAME"

    # Créer un lien symbolique vers le point de montage demandé
    if [ "$STORAGE_PATH" != "/$POOL_NAME" ]; then
        log "Création d'un lien symbolique de /$POOL_NAME vers $STORAGE_PATH..."
        ln -sf "/$POOL_NAME" "$STORAGE_PATH"
    fi

    success "Pool ZFS '$POOL_NAME' créé et configuré avec succès."
else
    # Créer une partition qui utilise tout le disque
    log "Création d'une partition sur $M2_DISK..."
    sgdisk -n 1:0:0 -t 1:8300 "$M2_DISK"
    partprobe "$M2_DISK"
    sleep 2

    # Identifier la partition créée
    PARTITION="${M2_DISK}p1"
    if [ ! -b "$PARTITION" ]; then
        # Certains disques utilisent un format différent (ex: /dev/sda1 au lieu de /dev/sdap1)
        PARTITION="${M2_DISK}1"
        if [ ! -b "$PARTITION" ]; then
            error "Impossible d'identifier la partition créée sur $M2_DISK"
        fi
    fi

    # Formater la partition avec le système de fichiers choisi
    log "Formatage de $PARTITION en $FS_TYPE..."
    if [ "$FS_TYPE" = "ext4" ]; then
        mkfs.ext4 -L vmstorage "$PARTITION"
    elif [ "$FS_TYPE" = "xfs" ]; then
        mkfs.xfs -L vmstorage "$PARTITION"
    else
        error "Système de fichiers non pris en charge: $FS_TYPE"
    fi

    # Monter la partition
    log "Montage de $PARTITION sur $STORAGE_PATH..."
    mount "$PARTITION" "$STORAGE_PATH"

    # Configurer le montage automatique au démarrage
    log "Configuration du montage automatique dans /etc/fstab..."
    UUID=$(blkid -s UUID -o value "$PARTITION")

    if [ -z "$UUID" ]; then
        error "Impossible de déterminer l'UUID de $PARTITION"
    fi

    # Vérifier si l'entrée existe déjà dans fstab
    if ! grep -q "$STORAGE_PATH" /etc/fstab; then
        echo "UUID=$UUID $STORAGE_PATH $FS_TYPE defaults 0 2" >> /etc/fstab
        success "Entrée ajoutée à /etc/fstab pour le montage automatique."
    else
        warning "Une entrée pour $STORAGE_PATH existe déjà dans /etc/fstab. Non modifiée."
    fi
fi

# Créer les sous-répertoires
log "Création des sous-répertoires..."
mkdir -p "$STORAGE_PATH/"{images,containers,backups,iso}
chmod 775 -R "$STORAGE_PATH"

# Ajouter les stockages dans Proxmox
log "Ajout des stockages dans Proxmox..."

# Vérifier si les stockages existent déjà
STORAGE_LIST=$(pvesm status)

if ! echo "$STORAGE_LIST" | grep -q "vm-storage"; then
    log "Ajout du stockage vm-storage..."
    pvesm add dir vm-storage --path "$STORAGE_PATH/images" --content images,rootdir
fi

if ! echo "$STORAGE_LIST" | grep -q "ct-storage"; then
    log "Ajout du stockage ct-storage..."
    pvesm add dir ct-storage --path "$STORAGE_PATH/containers" --content rootdir
fi

if ! echo "$STORAGE_LIST" | grep -q "backup"; then
    log "Ajout du stockage backup..."
    pvesm add dir backup --path "$STORAGE_PATH/backups" --content backup
fi

if ! echo "$STORAGE_LIST" | grep -q "iso"; then
    log "Ajout du stockage iso..."
    pvesm add dir iso --path "$STORAGE_PATH/iso" --content iso
fi

success "Configuration du stockage M.2 terminée avec succès!"
log "Stockages configurés:"
log "- vm-storage: $STORAGE_PATH/images"
log "- ct-storage: $STORAGE_PATH/containers"
log "- backup: $STORAGE_PATH/backups"
log "- iso: $STORAGE_PATH/iso"
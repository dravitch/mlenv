#!/bin/bash
# Script de configuration du disque M.2 comme stockage principal pour Proxmox
# À exécuter après l'installation de Proxmox et les scripts post-installation

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

# Identification du disque M.2
log "Identification des disques disponibles..."
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS

# Détection du disque M.2 (probablement sdb selon vos informations)
M2_DISK="/dev/sdb"

echo ""
echo -n "Veuillez confirmer le périphérique du disque M.2 [$M2_DISK]: "
read disk_input
if [ -n "$disk_input" ]; then
    M2_DISK="$disk_input"
fi

# Vérification que le disque existe
if [ ! -b "$M2_DISK" ]; then
    error "Le périphérique $M2_DISK n'existe pas. Veuillez vérifier le nom du périphérique."
fi

# Confirmation finale pour éviter les erreurs
echo ""
warning "ATTENTION: Toutes les données sur $M2_DISK seront effacées!"
echo -n "Êtes-vous sûr de vouloir continuer? (oui/non): "
read confirmation
if [ "$confirmation" != "oui" ]; then
    log "Opération annulée par l'utilisateur."
    exit 0
fi

# 1. Création de la partition sur le disque M.2
log "Création de la table de partitions sur $M2_DISK..."
fdisk $M2_DISK << EOF
o
n
p
1


w
EOF

sleep 2  # Attendre que le noyau détecte les changements

# Définir la partition (sdb1 si le disque est sdb)
M2_PARTITION="${M2_DISK}1"

# Vérifier que la partition a été créée
if [ ! -b "$M2_PARTITION" ]; then
    error "La partition $M2_PARTITION n'a pas été créée correctement."
fi

# 2. Formatage de la partition
log "Formatage de la partition $M2_PARTITION en ext4..."
mkfs.ext4 $M2_PARTITION

# 3. Création du point de montage et montage
log "Création du point de montage /mnt/vmstorage..."
mkdir -p /mnt/vmstorage
mount $M2_PARTITION /mnt/vmstorage

# 4. Configuration du montage automatique (fstab)
log "Configuration du montage automatique dans fstab..."
# Vérifier si une entrée pour /mnt/vmstorage existe déjà
if grep -q "/mnt/vmstorage" /etc/fstab; then
    # Remplacer l'entrée existante
    sed -i "\|/mnt/vmstorage|d" /etc/fstab
fi

# Ajouter la nouvelle entrée
echo "$M2_PARTITION /mnt/vmstorage ext4 defaults 0 2" >> /etc/fstab

# 5. Création des sous-répertoires
log "Création des sous-répertoires pour le stockage Proxmox..."
mkdir -p /mnt/vmstorage/{images,containers,backups,iso}
chmod 775 -R /mnt/vmstorage

# 6. Ajout du stockage dans Proxmox
log "Ajout du stockage dans Proxmox..."

# Vérification si les stockages existent déjà
if pvesm status | grep -q "vm-storage"; then
    log "Le stockage vm-storage existe déjà, suppression..."
    pvesm remove vm-storage
fi

if pvesm status | grep -q "ct-storage"; then
    log "Le stockage ct-storage existe déjà, suppression..."
    pvesm remove ct-storage
fi

if pvesm status | grep -q "backup"; then
    log "Le stockage backup existe déjà, suppression..."
    pvesm remove backup
fi

if pvesm status | grep -q "iso"; then
    log "Le stockage iso existe déjà, suppression..."
    pvesm remove iso
fi

# Ajout des nouveaux stockages
pvesm add dir vm-storage --path /mnt/vmstorage/images --content images,rootdir
pvesm add dir ct-storage --path /mnt/vmstorage/containers --content rootdir
pvesm add dir backup --path /mnt/vmstorage/backups --content backup
pvesm add dir iso --path /mnt/vmstorage/iso --content iso

# 7. Copie des ISO existantes si présentes
log "Copie des ISO existantes vers le nouveau répertoire..."
if [ -d "/var/lib/vz/template/iso" ]; then
    find /var/lib/vz/template/iso -name "*.iso" -exec cp -v {} /mnt/vmstorage/iso/ \;
fi

# 8. Vérification de la configuration
log "Vérification de la configuration du stockage..."
df -h /mnt/vmstorage
pvesm status

success "Configuration du disque M.2 terminée avec succès!"
log "Votre stockage est maintenant configuré comme suit:"
log "- VMs: /mnt/vmstorage/images (vm-storage)"
log "- Conteneurs: /mnt/vmstorage/containers (ct-storage)"
log "- Sauvegardes: /mnt/vmstorage/backups (backup)"
log "- ISOs: /mnt/vmstorage/iso (iso)"
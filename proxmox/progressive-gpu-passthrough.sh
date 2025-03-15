#!/bin/bash
# Script de configuration progressive du GPU passthrough pour Proxmox
# Projet MLENV - À exécuter sur l'hôte Proxmox

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

# Étape 1: Vérification de l'IOMMU
log "Vérification de l'IOMMU..."
if ! dmesg | grep -i iommu | grep -q "Adding to iommu group"; then
    warning "L'IOMMU ne semble pas être correctement activé."

    # Déterminer si c'est un processeur Intel ou AMD
    if grep -q "Intel" /proc/cpuinfo; then
        log "CPU Intel détecté. Il faut activer intel_iommu=on dans GRUB."
        IOMMU_FLAG="intel_iommu=on"
    else
        log "CPU AMD détecté. Il faut activer amd_iommu=on dans GRUB."
        IOMMU_FLAG="amd_iommu=on"
    fi

    # Ajouter l'option au fichier GRUB si pas déjà présente
    if ! grep -q "$IOMMU_FLAG" /etc/default/grub; then
        log "Ajout de $IOMMU_FLAG dans GRUB..."

        # Sauvegarder le fichier GRUB original
        cp /etc/default/grub /etc/default/grub.bak

        # Modifier le fichier GRUB
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet ${IOMMU_FLAG} iommu=pt\"/g" /etc/default/grub
        update-grub

        warning "GRUB a été mis à jour. Un redémarrage sera nécessaire après l'exécution de ce script."
        NEEDS_REBOOT=true
    fi
else
    success "IOMMU est correctement activé."
fi

# Étape 2: Configuration des modules VFIO
log "Configuration des modules VFIO..."
if ! grep -q "vfio" /etc/modules; then
    cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
EOF
    success "Modules VFIO ajoutés."
    MODULES_UPDATED=true
else
    log "Modules VFIO déjà configurés."
fi

# Étape 3: Identifier toutes les cartes GPU NVIDIA
log "Identification des GPUs NVIDIA..."
GPU_IDS=$(lspci -nn | grep -i nvidia | grep "VGA" | awk '{print $1}')
if [ -z "$GPU_IDS" ]; then
    warning "Aucune carte GPU NVIDIA détectée."
    echo "Voulez-vous continuer quand même? (y/n)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        error "Configuration annulée."
    fi
fi

log "GPUs NVIDIA détectées:"
for GPU_ID in $GPU_IDS; do
    GPU_INFO=$(lspci -s $GPU_ID -v | head -1)
    echo "  $GPU_INFO"
done

# Étape 4: Configurer VFIO pour toutes les cartes GPU NVIDIA
log "Configuration de VFIO pour les GPUs NVIDIA..."

# Extraire tous les IDs PCI des périphériques NVIDIA (GPU + Audio + USB + UC)
NVIDIA_IDS=$(lspci -nn | grep -i nvidia | grep -o -P "\[\K[0-9a-f]{4}:[0-9a-f]{4}\]" | tr -d '[]' | sort -u | tr '\n' ',' | sed 's/,$//')

if [ -n "$NVIDIA_IDS" ]; then
    echo "options vfio-pci ids=$NVIDIA_IDS" > /etc/modprobe.d/vfio.conf
    success "IDs NVIDIA configurés pour VFIO: $NVIDIA_IDS"
    VFIO_CONFIGURED=true
else
    warning "Impossible d'extraire les IDs des GPUs NVIDIA."
    echo "Voulez-vous continuer quand même? (y/n)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        error "Configuration annulée."
    fi
fi

# Étape 5: Bloquer les pilotes NVIDIA natifs sur l'hôte
log "Blocage des pilotes NVIDIA sur l'hôte..."
cat > /etc/modprobe.d/blacklist-nvidia.conf << EOF
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF
success "Pilotes NVIDIA bloqués sur l'hôte."
BLACKLIST_UPDATED=true

# Étape 6: Configuration KVM pour NVIDIA
log "Configuration des options KVM pour NVIDIA..."
echo "options kvm ignore_msrs=1 report_ignored_msrs=0" > /etc/modprobe.d/kvm.conf
success "Configuration KVM pour NVIDIA ajoutée."

# Étape 7: Mettre à jour l'initramfs
log "Mise à jour de l'initramfs..."
update-initramfs -u
success "Initramfs mis à jour."

# Étape 8: Création des scripts utilitaires pour le passthrough

# Script pour configurer toutes les cartes GPU dans une VM
log "Création du script pour ajouter tous les GPUs à une VM..."
cat > /usr/local/bin/configure_all_gpus.sh << 'EOF'
#!/bin/bash
# Script pour ajouter tous les GPUs NVIDIA à une VM spécifiée

if [ $# -lt 1 ]; then
    echo "Usage: $0 <VM_ID> [--force]"
    echo "Exemple: $0 100"
    exit 1
fi

VM_ID=$1
FORCE=$2

# Vérifier si la VM existe
if ! qm status $VM_ID &> /dev/null; then
    echo "Erreur: VM $VM_ID introuvable."
    exit 1
fi

# Arrêter la VM si elle est en marche et que --force est spécifié
if qm status $VM_ID | grep -q running; then
    if [ "$FORCE" == "--force" ]; then
        echo "Arrêt de la VM $VM_ID..."
        qm stop $VM_ID
        sleep 5
    else
        echo "Erreur: La VM $VM_ID est en cours d'exécution. Utilisez --force pour l'arrêter automatiquement."
        exit 1
    fi
fi

# Récupérer les configurations hostpci existantes
EXISTING_HOSTPCI=$(qm config $VM_ID | grep hostpci | cut -d: -f1)

# Supprimer les configurations existantes
for CONFIG in $EXISTING_HOSTPCI; do
    echo "Suppression de la configuration $CONFIG..."
    qm set $VM_ID --delete $CONFIG
done

# Identifier les GPU NVIDIA
GPU_ADDRESSES=$(lspci -nn | grep -i nvidia | grep -i vga | awk '{print $1}')
if [ -z "$GPU_ADDRESSES" ]; then
    echo "Aucun GPU NVIDIA trouvé."
    exit 1
fi

# Ajouter chaque GPU à la VM
INDEX=0
for GPU in $GPU_ADDRESSES; do
    echo "Ajout du GPU $GPU à la VM $VM_ID (position $INDEX)..."

    # Ajouter x-vga=on uniquement au premier GPU
    if [ $INDEX -eq 0 ]; then
        qm set $VM_ID --hostpci${INDEX} ${GPU},pcie=1,x-vga=on
    else
        qm set $VM_ID --hostpci${INDEX} ${GPU},pcie=1
    fi

    INDEX=$((INDEX+1))
done

echo "Configuration terminée. $INDEX GPU(s) ajouté(s) à la VM $VM_ID."
echo "Vous pouvez maintenant démarrer la VM avec: qm start $VM_ID"
EOF

chmod +x /usr/local/bin/configure_all_gpus.sh
success "Script de configuration des GPUs créé: /usr/local/bin/configure_all_gpus.sh"

# Script de secours pour restaurer la configuration
log "Création du script de secours pour restaurer la configuration..."
cat > /boot/restore-boot.sh << 'EOF'
#!/bin/bash
# Script de secours pour restaurer la configuration de démarrage

# Remonter le système de fichiers en lecture-écriture
mount -o remount,rw /

# Désactiver les fichiers de configuration problématiques
if [ -f /etc/modprobe.d/vfio.conf ]; then
    mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.disabled
fi

if [ -f /etc/modprobe.d/blacklist-nvidia.conf ]; then
    mv /etc/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf.disabled
fi

# Restaurer GRUB sans IOMMU
if [ -f /etc/default/grub ]; then
    sed -i 's/intel_iommu=on//g' /etc/default/grub
    sed -i 's/amd_iommu=on//g' /etc/default/grub
    sed -i 's/iommu=pt//g' /etc/default/grub
    update-grub
fi

# Mettre à jour l'initramfs
update-initramfs -u -k all

echo "Configuration restaurée. Redémarrez avec 'reboot'"
EOF

chmod +x /boot/restore-boot.sh
success "Script de restauration créé: /boot/restore-boot.sh"

# Message final
echo
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}  Configuration du GPU Passthrough terminée!  ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo

log "Pour finaliser la configuration:"

if [ "$NEEDS_REBOOT" = true ] || [ "$MODULES_UPDATED" = true ] || [ "$VFIO_CONFIGURED" = true ] || [ "$BLACKLIST_UPDATED" = true ]; then
    echo "1. Redémarrez le système: 'reboot'"
    echo "2. Après le redémarrage, vérifiez que VFIO a bien pris en charge les GPUs:"
    echo "   'lspci -nnk | grep -i nvidia -A3'"
else
    echo "1. Vérifiez que VFIO a bien pris en charge les GPUs:"
    echo "   'lspci -nnk | grep -i nvidia -A3'"
fi

echo
echo "3. Pour configurer le passthrough GPU pour une VM:"
echo "   '/usr/local/bin/configure_all_gpus.sh VM_ID'"
echo "   Exemple: '/usr/local/bin/configure_all_gpus.sh 100'"
echo
echo "4. Pour la VM, assurez-vous d'utiliser:"
echo "   - Type de machine: q35"
echo "   - BIOS: OVMF (UEFI)"
echo "   - Arguments: -cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"
echo
echo "5. En cas de problème au démarrage, utilisez le script de secours:"
echo "   'bash /boot/restore-boot.sh' (depuis un shell de récupération)"
echo
echo "Note: Référez-vous à la documentation pour plus de détails sur la configuration des VMs."

# Demander si l'utilisateur veut redémarrer
if [ "$NEEDS_REBOOT" = true ] || [ "$MODULES_UPDATED" = true ] || [ "$VFIO_CONFIGURED" = true ] || [ "$BLACKLIST_UPDATED" = true ]; then
    read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_choice
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
        log "Redémarrage du système..."
        reboot
    else
        warning "N'oubliez pas de redémarrer manuellement pour appliquer toutes les modifications!"
    fi
fi
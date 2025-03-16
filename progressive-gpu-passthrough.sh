#!/bin/bash
# Script de configuration progressive du GPU passthrough pour Proxmox
# À exécuter après l'installation et la post-configuration de Proxmox

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

# Vérification que Proxmox VE est installé
if ! command -v pveversion &> /dev/null; then
    error "Proxmox VE ne semble pas être installé. Ce script est destiné à une configuration après installation."
fi

log "Démarrage de la configuration progressive du GPU passthrough..."

# Étape 1: Vérification des prérequis matériels
log "1. Vérification du support IOMMU..."
if ! dmesg | grep -i -e DMAR -e IOMMU &> /dev/null; then
    warning "IOMMU ne semble pas être activé. Vérification du BIOS et configuration de GRUB..."

    # Déterminer si c'est un processeur Intel ou AMD
    if grep -q "Intel" /proc/cpuinfo; then
        log "Processeur Intel détecté."
        IOMMU_OPTION="intel_iommu=on"
    else
        log "Processeur AMD détecté."
        IOMMU_OPTION="amd_iommu=on"
    fi

    # Vérifier si l'option IOMMU est déjà configurée dans GRUB
    if ! grep -q "$IOMMU_OPTION" /etc/default/grub; then
        log "Ajout des options IOMMU à GRUB..."
        # Sauvegarde du fichier GRUB
        cp /etc/default/grub /etc/default/grub.bak

        # Ajouter l'option au fichier GRUB
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet ${IOMMU_OPTION} iommu=pt\"/g" /etc/default/grub
        update-grub

        log "Options IOMMU ajoutées à GRUB. Un redémarrage sera nécessaire."
        REBOOT_REQUIRED=true
    else
        log "Options IOMMU déjà configurées dans GRUB."
    fi
else
    success "Support IOMMU détecté."
fi

# Étape 2: Configuration des modules VFIO
log "2. Configuration des modules VFIO..."

# Création du répertoire recovery pour les scripts de récupération
mkdir -p /boot/recovery

# Vérifier si les modules VFIO sont déjà configurés
if ! grep -q "vfio" /etc/modules; then
    log "Ajout des modules VFIO..."
    cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
EOF
    success "Modules VFIO ajoutés."
else
    log "Modules VFIO déjà configurés."
fi

# Étape 3: Identifier les cartes GPU NVIDIA
log "3. Identification des GPUs NVIDIA..."
GPU_IDS=$(lspci -nn | grep -i nvidia | awk '{print $1}')
if [ -z "$GPU_IDS" ]; then
    error "Aucune carte GPU NVIDIA détectée."
fi

log "GPUs NVIDIA détectées:"
for GPU_ID in $GPU_IDS; do
    GPU_INFO=$(lspci -s $GPU_ID -v | head -1)
    echo "  $GPU_INFO"
done

# Étape 4: Extraire les identifiants vendeur:produit pour VFIO
log "4. Extraction des identifiants PCI des GPUs NVIDIA..."
NVIDIA_IDS=$(lspci -nn | grep -i nvidia | grep -o -P "\[\K[0-9a-f]{4}:[0-9a-f]{4}\]" | tr -d '[]' | sort -u | tr '\n' ',' | sed 's/,$//')

if [ -z "$NVIDIA_IDS" ]; then
    error "Impossible d'extraire les IDs des GPUs NVIDIA."
fi

log "IDs NVIDIA trouvés: $NVIDIA_IDS"

# Création du script de récupération
log "5. Création du script de récupération..."
cat > /boot/recovery/restore-boot.sh << 'EOF'
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
chmod +x /boot/recovery/restore-boot.sh
success "Script de récupération créé: /boot/recovery/restore-boot.sh"

# Étape 5: Configuration progressive pour un GPU
log "5. Configuration progressive du passthrough GPU..."

# Demander à l'utilisateur s'il veut procéder
echo -e "${YELLOW}Cette étape va configurer le passthrough GPU progressivement, en commençant par une seule carte.${NC}"
read -p "Voulez-vous procéder à la configuration progressive? [y/N]: " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    log "Configuration progressive annulée par l'utilisateur."
    exit 0
fi

# Sauvegarde des fichiers existants
mkdir -p /etc/modprobe.d/backup
if [ -f /etc/modprobe.d/vfio.conf ]; then
    cp /etc/modprobe.d/vfio.conf /etc/modprobe.d/backup/vfio.conf.$(date +%Y%m%d%H%M%S)
fi

# Sélectionner le premier GPU
FIRST_GPU_ID=$(echo $NVIDIA_IDS | cut -d',' -f1)

log "Configuration du passthrough pour le premier GPU: $FIRST_GPU_ID"

# Créer le fichier de configuration VFIO avec un seul GPU
echo "options vfio-pci ids=$FIRST_GPU_ID" > /etc/modprobe.d/vfio.conf

# Étape 6: Blocage des pilotes NVIDIA natifs sur l'hôte
log "6. Blocage des pilotes NVIDIA natifs sur l'hôte..."
cat > /etc/modprobe.d/blacklist-nvidia.conf << EOF
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF
success "Pilotes NVIDIA bloqués sur l'hôte."

# Étape 7: Configuration KVM pour les GPUs NVIDIA
log "7. Configuration de KVM pour les GPUs NVIDIA..."
echo "options kvm ignore_msrs=1 report_ignored_msrs=0" > /etc/modprobe.d/kvm.conf
success "Configuration KVM ajoutée."

# Étape 8: Création des scripts utilitaires
log "8. Création des scripts utilitaires pour le passthrough GPU..."

# Script pour ajouter un GPU à une VM
cat > /usr/local/bin/add_gpu_to_vm.sh << 'EOF'
#!/bin/bash
# Script pour ajouter un GPU à une VM
# Usage: add_gpu_to_vm.sh VM_ID GPU_ID [x-vga]

if [ $# -lt 2 ]; then
    echo "Usage: $0 VM_ID GPU_ID [x-vga]"
    echo "Exemple: $0 100 01:00.0 x-vga"
    exit 1
fi

VM_ID=$1
GPU_ID=$2
X_VGA=$3

# Vérifier si la VM existe
if ! qm status $VM_ID &>/dev/null; then
    echo "Erreur: VM $VM_ID n'existe pas."
    exit 1
fi

# Vérifier si le GPU existe
if ! lspci -s $GPU_ID &>/dev/null; then
    echo "Erreur: GPU $GPU_ID n'existe pas."
    exit 1
fi

# Arrêter la VM si elle est en cours d'exécution
if qm status $VM_ID | grep -q running; then
    echo "Arrêt de la VM $VM_ID..."
    qm stop $VM_ID
    sleep 2
fi

# Ajouter le GPU à la VM
if [ "$X_VGA" = "x-vga" ] || [ "$X_VGA" = "x-vga=on" ]; then
    echo "Ajout du GPU $GPU_ID avec option x-vga=on à la VM $VM_ID..."
    qm set $VM_ID --hostpci0 $GPU_ID,pcie=1,x-vga=on
else
    echo "Ajout du GPU $GPU_ID à la VM $VM_ID..."
    qm set $VM_ID --hostpci0 $GPU_ID,pcie=1
fi

echo "GPU ajouté avec succès. Vous pouvez maintenant démarrer la VM avec: qm start $VM_ID"
EOF
chmod +x /usr/local/bin/add_gpu_to_vm.sh

# Script pour ajouter tous les GPUs à une VM
cat > /usr/local/bin/add_multiple_gpus_to_vm.sh << 'EOF'
#!/bin/bash
# Script pour ajouter tous les GPUs à une VM
# Usage: add_multiple_gpus_to_vm.sh VM_ID

if [ $# -lt 1 ]; then
    echo "Usage: $0 VM_ID"
    echo "Exemple: $0 100"
    exit 1
fi

VM_ID=$1

# Vérifier si la VM existe
if ! qm status $VM_ID &>/dev/null; then
    echo "Erreur: VM $VM_ID n'existe pas."
    exit 1
fi

# Arrêter la VM si elle est en cours d'exécution
if qm status $VM_ID | grep -q running; then
    echo "Arrêt de la VM $VM_ID..."
    qm stop $VM_ID
    sleep 2
fi

# Supprimer toutes les configurations hostpci existantes
for i in $(qm config $VM_ID | grep hostpci | cut -d: -f1); do
    echo "Suppression de la configuration $i..."
    qm set $VM_ID --delete $i
done

# Obtenir la liste des GPUs NVIDIA
GPU_IDS=($(lspci -nn | grep -i nvidia | grep -i vga | awk '{print $1}'))

if [ ${#GPU_IDS[@]} -eq 0 ]; then
    echo "Aucun GPU NVIDIA détecté."
    exit 1
fi

# Ajouter le premier GPU avec x-vga=on
echo "Ajout du premier GPU ${GPU_IDS[0]} avec x-vga=on..."
qm set $VM_ID --hostpci0 ${GPU_IDS[0]},pcie=1,x-vga=on

# Ajouter les GPUs restants
for i in $(seq 1 $((${#GPU_IDS[@]}-1))); do
    echo "Ajout du GPU ${GPU_IDS[$i]}..."
    qm set $VM_ID --hostpci$i ${GPU_IDS[$i]},pcie=1
done

echo "Tous les GPUs (${#GPU_IDS[@]}) ont été ajoutés à la VM $VM_ID."
echo "Vous pouvez maintenant démarrer la VM avec: qm start $VM_ID"
EOF
chmod +x /usr/local/bin/add_multiple_gpus_to_vm.sh

success "Scripts utilitaires créés:"
success "- /usr/local/bin/add_gpu_to_vm.sh"
success "- /usr/local/bin/add_multiple_gpus_to_vm.sh"

# Étape 9: Mettre à jour l'initramfs
log "9. Mise à jour de l'initramfs..."
update-initramfs -u -k all
success "Initramfs mis à jour."

# Message final et instructions
cat << EOF

==========================================================================
CONFIGURATION DU GPU PASSTHROUGH TERMINÉE
==========================================================================

Pour finaliser la configuration:
1. Redémarrez le système: 'reboot'
2. Après le redémarrage, vérifiez que VFIO a bien pris en charge les GPUs:
   'lspci -nnk | grep -i nvidia -A3'

3. Deux scripts utilitaires ont été créés pour faciliter le passthrough GPU:

   - Pour ajouter un seul GPU à une VM:
     /usr/local/bin/add_gpu_to_vm.sh VM_ID GPU_ID [x-vga=on]
     Exemple: /usr/local/bin/add_gpu_to_vm.sh 100 01:00.0 x-vga=on

   - Pour ajouter tous les GPUs à une VM:
     /usr/local/bin/add_multiple_gpus_to_vm.sh VM_ID
     Exemple: /usr/local/bin/add_multiple_gpus_to_vm.sh 100

4. Assurez-vous que la VM est configurée avec:
   - Type de machine: q35
   - BIOS: OVMF (UEFI)
   - CPU: type 'host'
   - Option de machine additionnelle: 'args: -cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off''

5. Dans votre VM, installez les pilotes NVIDIA appropriés.

==========================================================================
EOF

log "Un redémarrage est nécessaire pour appliquer les changements."
read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log "Redémarrage du système..."
    reboot
fi
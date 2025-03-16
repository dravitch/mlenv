#!/bin/bash
# Script de création et configuration de la VM de machine learning
# À exécuter après la configuration de Proxmox et du passthrough GPU

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
if ! command -v qm &> /dev/null; then
    error "Proxmox VE ne semble pas être installé. Ce script utilise les commandes Proxmox (qm)."
fi

# Paramètres de la VM (modifiables)
VM_ID=${1:-101}
VM_NAME="MachineLearningGPU"
VM_MEMORY=8192
VM_CORES=2
VM_DISK_SIZE=40
BRIDGE_INTERFACE="vmbr0"
ISO_STORE="local"
ISO_FILE="ubuntu-22.04.4-live-server-amd64.iso"
STORAGE="vm-storage"

log "Configuration de la VM de machine learning ($VM_NAME)..."

# Vérifier si la VM existe déjà
if qm status $VM_ID &>/dev/null; then
    warning "Une VM avec ID $VM_ID existe déjà."
    read -p "Voulez-vous la supprimer et la recréer? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Suppression de la VM existante..."
        qm stop $VM_ID &>/dev/null || true
        qm destroy $VM_ID
    else
        error "Configuration annulée par l'utilisateur."
    fi
fi

# Vérifier si l'ISO existe
ISO_PATH="$ISO_STORE:iso/$ISO_FILE"
if ! pvesm list $ISO_STORE | grep -q "$ISO_FILE"; then
    warning "L'ISO $ISO_FILE n'existe pas dans le stockage $ISO_STORE."
    log "Liste des ISO disponibles:"
    pvesm list $ISO_STORE | grep "iso" || true

    read -p "Voulez-vous continuer sans ISO ou spécifier un autre chemin? [C]ontinuer/[S]pécifier/[A]nnuler: " iso_choice
    case $iso_choice in
        [Ss]*)
            read -p "Entrez le chemin complet de l'ISO (ex: local:iso/debian-12.4.0-amd64-netinst.iso): " ISO_PATH
            ;;
        [Cc]*)
            ISO_PATH=""
            warning "Aucune ISO spécifiée. Vous devrez ajouter le média d'installation manuellement."
            ;;
        *)
            error "Configuration annulée par l'utilisateur."
            ;;
    esac
fi

# Création de la VM
log "Création de la VM $VM_NAME avec ID $VM_ID..."
qm create $VM_ID --name $VM_NAME --memory $VM_MEMORY --cores $VM_CORES \
    --net0 virtio,bridge=$BRIDGE_INTERFACE \
    --bios ovmf \
    --machine q35 \
    --cpu host \
    --ostype l26 \
    --agent 1

# Ajout du disque EFI
log "Ajout du disque EFI..."
qm set $VM_ID --efidisk0 $STORAGE:1

# Ajout du disque principal
log "Ajout du disque principal..."
qm set $VM_ID --sata0 $STORAGE:$VM_DISK_SIZE,ssd=1

# Configuration des paramètres CPU avancés pour le passthrough NVIDIA
log "Configuration des paramètres CPU avancés..."
qm set $VM_ID --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"

# Ajout de l'ISO si spécifiée
if [ -n "$ISO_PATH" ]; then
    log "Ajout de l'ISO d'installation..."
    qm set $VM_ID --ide2 $ISO_PATH,media=cdrom

    # Configuration du démarrage sur l'ISO
    qm set $VM_ID --boot "order=ide2;sata0"
else
    # Configuration du démarrage sur le disque
    qm set $VM_ID --boot "order=sata0"
fi

success "VM $VM_NAME créée avec succès!"

# Détection des GPUs NVIDIA après celles qui pourraient être déjà attribuées
log "Détection des GPUs NVIDIA pour le passthrough..."

# Obtenir la liste complète des GPUs
ALL_GPU_IDS=$(lspci -nn | grep -i nvidia | grep -i vga | awk '{print $1}')

# Vérifier les GPUs déjà attribuées à d'autres VMs
USED_GPUS=""
for vm in $(qm list | tail -n +2 | awk '{print $1}'); do
    if [ "$vm" != "$VM_ID" ]; then
        vm_gpus=$(qm config $vm | grep hostpci | grep -o -P "(?<=hostpci\d+: )[\w:\.]+")
        if [ -n "$vm_gpus" ]; then
            USED_GPUS="$USED_GPUS $vm_gpus"
        fi
    fi
done

# Filtrer pour obtenir les GPUs disponibles
GPU_IDS=""
for gpu in $ALL_GPU_IDS; do
    if ! echo "$USED_GPUS" | grep -q "$gpu"; then
        GPU_IDS="$GPU_IDS$gpu"$'\n'
    fi
done

# Supprimer la dernière ligne vide
GPU_IDS=$(echo "$GPU_IDS" | sed '/^$/d')

if [ -z "$GPU_IDS" ]; then
    warning "Aucun GPU NVIDIA disponible. Toutes les cartes sont peut-être déjà attribuées à d'autres VMs."
else
    log "GPUs NVIDIA disponibles:"
    echo "$GPU_IDS"

    # Demander à l'utilisateur s'il veut configurer le passthrough GPU
    read -p "Voulez-vous configurer le passthrough GPU pour cette VM? [y/N]: " gpu_choice
    if [[ "$gpu_choice" =~ ^[Yy]$ ]]; then
        # Demander le nombre de GPUs à attribuer
        GPU_COUNT=$(echo "$GPU_IDS" | wc -l)
        echo "Il y a $GPU_COUNT GPUs disponibles."
        read -p "Combien de GPUs voulez-vous attribuer à cette VM? [1-$GPU_COUNT]: " gpu_num

        # Validation de l'entrée
        if ! [[ "$gpu_num" =~ ^[0-9]+$ ]] || [ "$gpu_num" -lt 1 ] || [ "$gpu_num" -gt "$GPU_COUNT" ]; then
            warning "Nombre de GPUs invalide. Attribution de tous les GPUs disponibles."
            gpu_num=$GPU_COUNT
        fi

        # Obtenir les premiers N GPUs
        SELECTED_GPUS=$(echo "$GPU_IDS" | head -n $gpu_num)

        # Arrêter la VM si elle est en cours d'exécution
        qm stop $VM_ID &>/dev/null || true

        # Ajouter le premier GPU avec x-vga=on
        FIRST_GPU=$(echo "$SELECTED_GPUS" | head -n 1)
        log "Ajout du GPU $FIRST_GPU avec x-vga=on..."
        qm set $VM_ID --hostpci0 $FIRST_GPU,pcie=1,x-vga=on

        # Ajouter les GPUs supplémentaires sans x-vga=on
        if [ "$gpu_num" -gt 1 ]; then
            i=1
            echo "$SELECTED_GPUS" | tail -n +2 | while read gpu; do
                log "Ajout du GPU $gpu..."
                qm set $VM_ID --hostpci$i $gpu,pcie=1
                i=$((i+1))
            done
        fi

        success "Passthrough GPU configuré avec $gpu_num GPUs."
    else
        log "Passthrough GPU non configuré. Vous pouvez le faire manuellement plus tard."
    fi
fi

# Demander s'il faut démarrer la VM
read -p "Voulez-vous démarrer la VM maintenant? [y/N]: " start_choice
if [[ "$start_choice" =~ ^[Yy]$ ]]; then
    log "Démarrage de la VM $VM_NAME..."
    qm start $VM_ID

    # Afficher des instructions pour accéder à la console
    log "Vous pouvez accéder à la console via l'interface web Proxmox."
    log "URL: https://$(hostname -I | awk '{print $1}'):8006"
fi

log "Étapes suivantes:"
log "1. Installez Ubuntu Server sur la VM via la console Proxmox"
log "2. Après l'installation, exécutez le script setup-ml.sh dans la VM"
log "3. Configurez l'environnement de machine learning selon vos besoins"

success "Configuration de la VM de machine learning terminée!"
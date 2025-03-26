#!/bin/bash
# Script de création et configuration de la VM de backtesting
# À exécuter sur l'hôte Proxmox
# Partie du projet PredatorX - https://github.com/dravitch/mlenv
# Version mise à jour avec la configuration fonctionnelle pour le passthrough GPU
## Pour créer une VM avec 2 GPUs (par défaut)
  #bash setup-backtesting-vm-updated.sh
## Pour créer une VM avec un nombre spécifique de GPUs (ex: 6)
  #bash setup-backtesting-vm-updated.sh 100 6

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

# Vérification que le script est exécuté sur Proxmox
if ! command -v qm &> /dev/null; then
    error "Ce script doit être exécuté sur l'hôte Proxmox (commande qm non trouvée)"
fi

# Paramètres de la VM (modifiables)
VM_ID=${1:-100}
VM_NAME="BacktestingVM"
VM_MEMORY=8192  # 8 GB RAM
VM_CORES=2      # 2 cores CPU
STORAGE="vm-storage"
BRIDGE="vmbr0"
VM_DISK_SIZE=60  # 60 GB
ISO_PATH="local:iso/ubuntu-22.04.4-live-server-amd64.iso"

# Nombre de GPUs à configurer (modifiable)
GPU_COUNT=${2:-2}  # Par défaut, 2 GPUs

log "Configuration de la VM de backtesting ($VM_NAME)..."

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

# Création de la VM de base
log "Création de la VM $VM_NAME avec ID $VM_ID..."
qm create $VM_ID --name "$VM_NAME" --memory $VM_MEMORY --cores $VM_CORES \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1 \
  --onboot 1

# Configuration des options CPU avancées pour NVIDIA
log "Configuration des paramètres CPU avancés pour le passthrough GPU..."
qm set $VM_ID --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"

# Ajout du disque EFI
log "Création du disque EFI pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --efidisk0 $STORAGE:$VM_ID/vm-$VM_ID-disk-0.raw,size=128K

# Ajout du disque principal
log "Configuration du disque principal pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --sata0 $STORAGE:$VM_ID/vm-$VM_ID-disk-2.raw,size=${VM_DISK_SIZE}G,ssd=1

# Configuration du réseau (utiliser e1000 qui a fonctionné)
log "Configuration du réseau pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --net0 e1000,bridge=$BRIDGE

# Configuration du contrôleur SCSI
log "Configuration du contrôleur SCSI pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --scsihw virtio-scsi-pci

# Désactivation de la tablette
log "Désactivation de la tablette pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --tablet 0

# Configuration de la carte VGA
log "Configuration de la carte VGA pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --vga std

# Vérifier si l'ISO existe
if pvesm list local | grep -q $(basename "$ISO_PATH"); then
    # Ajout de l'ISO
    log "Configuration de l'ISO pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --ide2 $ISO_PATH,media=cdrom

    # Configuration du démarrage sur l'ISO
    qm set $VM_ID --boot "order=ide2;sata0"
else
    warning "ISO Ubuntu 22.04 non trouvé. Veuillez ajouter un média d'installation manuellement."
    qm set $VM_ID --boot "order=sata0"
fi

# Configuration du passthrough GPU - Utilisation de la méthode qui fonctionne
log "Configuration du passthrough GPU avec $GPU_COUNT GPUs..."

# Configuration du premier GPU (avec bus complet et x-vga=1)
log "Configuration du passthrough GPU 0 pour la VM $VM_NAME avec ID $VM_ID..."
qm set $VM_ID --hostpci0 0000:01:00,x-vga=1

# Configuration des GPUs additionnels selon le nombre demandé
if [ "$GPU_COUNT" -ge 2 ]; then
    log "Configuration du passthrough GPU 1 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci2 0000:02:00.0,pcie=1
fi

if [ "$GPU_COUNT" -ge 3 ]; then
    log "Configuration du passthrough GPU 2 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci3 0000:09:00.0,pcie=1
fi

if [ "$GPU_COUNT" -ge 4 ]; then
    log "Configuration du passthrough GPU 3 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci4 0000:04:00.0,pcie=1
fi

if [ "$GPU_COUNT" -ge 5 ]; then
    log "Configuration du passthrough GPU 4 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci5 0000:06:00.0,pcie=1
fi

if [ "$GPU_COUNT" -ge 6 ]; then
    log "Configuration du passthrough GPU 5 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci6 0000:07:00.0,pcie=1
fi

if [ "$GPU_COUNT" -ge 7 ]; then
    log "Configuration du passthrough GPU 6 pour la VM $VM_NAME avec ID $VM_ID..."
    qm set $VM_ID --hostpci7 0000:08:00.0,pcie=1
fi

success "Passthrough GPU configuré avec $GPU_COUNT GPUs."

# Récapitulatif de la configuration
log "Récapitulatif de la configuration:"
log "- ID VM: $VM_ID"
log "- Nom: $VM_NAME"
log "- Mémoire: ${VM_MEMORY}MB"
log "- CPU: $VM_CORES cœurs"
log "- Disque: ${VM_DISK_SIZE}GB SSD"
log "- GPUs: $GPU_COUNT"
log "- OS: Ubuntu 22.04"

# Afficher la configuration complète
log "Configuration complète de la VM:"
qm config $VM_ID

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
log "2. Après l'installation, exécutez le script vm/setup-backtesting.sh dans la VM"
log "3. Configurez l'environnement de backtesting selon vos besoins"

success "Configuration de la VM de backtesting terminée!"
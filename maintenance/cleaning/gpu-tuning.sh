#!/bin/bash
# gpu-tuning.sh - Script d'optimisation pour environnement multi-GPU
# À exécuter en tant que root après installation et vérification

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root"
fi

# 1. Vérifier la détection GPU actuelle
log "Vérification de la détection GPU actuelle..."
if ! command -v nvidia-smi &> /dev/null; then
    error "nvidia-smi n'est pas installé. Veuillez installer les pilotes NVIDIA d'abord."
fi

GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null || echo "0")
log "Nombre de GPUs détectés actuellement: $GPU_COUNT"

PCI_GPU_COUNT=$(lspci | grep -i nvidia | grep -i vga | wc -l)
log "Nombre de GPUs NVIDIA détectés par PCI: $PCI_GPU_COUNT"

# Créer une sauvegarde des configurations existantes
BACKUP_DIR="/root/gpu_config_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# 2. Configuration du fichier /etc/modprobe.d/nvidia.conf
log "Configuration des options de module noyau NVIDIA..."
if [ -f "/etc/modprobe.d/nvidia.conf" ]; then
    cp /etc/modprobe.d/nvidia.conf $BACKUP_DIR/
    log "Sauvegarde de l'ancien fichier nvidia.conf dans $BACKUP_DIR"
fi

cat > /etc/modprobe.d/nvidia.conf << EOF
# Configuration optimisée pour multi-GPU
options nvidia NVreg_EnablePCIeGen3=0
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"
options nvidia NVreg_RegistryDwords="RmPVMRL=0x1"
EOF

success "Fichier /etc/modprobe.d/nvidia.conf créé/mis à jour"

# 3. Modification de GRUB pour optimiser les performances PCIe
log "Configuration de GRUB pour optimiser les performances PCIe..."
if [ -f "/etc/default/grub" ]; then
    cp /etc/default/grub $BACKUP_DIR/

    # Vérifier si les paramètres sont déjà présents
    GRUB_CMDLINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | cut -d'"' -f2)

    # Paramètres à ajouter
    PARAMS_TO_ADD="pcie_aspm=off pci=noaer pci=realloc"
    PARAMS_ARRAY=($PARAMS_TO_ADD)

    # Vérifier et ajouter chaque paramètre si nécessaire
    NEW_PARAMS=""
    for param in "${PARAMS_ARRAY[@]}"; do
        if ! echo "$GRUB_CMDLINE" | grep -q "$param"; then
            NEW_PARAMS="$NEW_PARAMS $param"
        fi
    done

    if [ -n "$NEW_PARAMS" ]; then
        # Ajouter les nouveaux paramètres
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $NEW_PARAMS\"/" /etc/default/grub
        update-grub
        success "Paramètres GRUB mis à jour: $NEW_PARAMS"
    else
        log "Paramètres GRUB déjà configurés correctement"
    fi
else
    error "Fichier de configuration GRUB non trouvé"
fi

# 4. Création du script de détection de tous les GPUs
log "Création du script de détection de tous les GPUs..."

# Récupérer les identifiants PCI des GPUs
GPU_ADDRESSES=$(lspci | grep -i nvidia | grep -i vga | awk '{print $1}' | sort)

# Créer le script
cat > /usr/local/bin/enable-all-gpus.sh << EOF
#!/bin/bash
# Script pour forcer la détection de tous les GPUs
# Créé automatiquement par gpu-tuning.sh

echo "Forçage de la détection des GPUs..."

# Essayer d'abord de récupérer les GPUs dans nvidia-smi
nvidia-smi &>/dev/null
sleep 2

# Si des GPUs sont manquants, forcer la redétection
for i in {0..7}; do
EOF

# Ajouter chaque GPU détecté au script
for addr in $GPU_ADDRESSES; do
    bus=$(echo $addr | cut -d: -f1)
    device=$(echo $addr | cut -d: -f2 | cut -d. -f1)
    echo "  echo 1 > /sys/bus/pci/devices/0000:${bus}:${device}.\$i/remove 2>/dev/null || true" >> /usr/local/bin/enable-all-gpus.sh
done

cat >> /usr/local/bin/enable-all-gpus.sh << EOF
done

echo "Rescanning PCI bus..."
echo 1 > /sys/bus/pci/rescan
sleep 2

echo "Rechargeant les modules NVIDIA..."
rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
modprobe nvidia
sleep 1

echo "Nombre de GPUs détectés après activation:"
nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null || echo "Erreur: nvidia-smi ne détecte pas de GPU"

echo "Terminé. Vérifiez avec 'nvidia-smi'"
EOF

chmod +x /usr/local/bin/enable-all-gpus.sh
success "Script /usr/local/bin/enable-all-gpus.sh créé"

# 5. Configuration des paramètres système pour ML
log "Configuration des paramètres système pour ML..."

# 5.1 Optimisation de swappiness (moins de swap, plus de RAM)
echo "vm.swappiness=10" > /etc/sysctl.d/99-gpu-ml-optimizations.conf

# 5.2 Optimisation de transparent hugepage (meilleure performance pour grandes allocations)
echo "vm.nr_hugepages=2048" >> /etc/sysctl.d/99-gpu-ml-optimizations.conf
echo "always" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

# 5.3 Appliquer les changements
sysctl -p /etc/sysctl.d/99-gpu-ml-optimizations.conf
success "Paramètres système pour ML configurés"

# 6. Activer le mode de persistance NVIDIA pour améliorer les performances
log "Activation du mode de persistance NVIDIA..."
nvidia-smi -pm 1
success "Mode de persistance NVIDIA activé"

# 7. Configuration des limites de ressources pour l'utilisateur backtester
log "Configuration des limites de ressources pour l'utilisateur ML..."

if id backtester &>/dev/null; then
    cat > /etc/security/limits.d/99-gpu-ml-user.conf << EOF
# Augmentation des limites pour l'utilisateur de backtesting/ML
backtester soft nofile 65536
backtester hard nofile 65536
backtester soft memlock unlimited
backtester hard memlock unlimited
EOF
    success "Limites de ressources configurées pour l'utilisateur backtester"
else
    warning "Utilisateur backtester non trouvé, limites de ressources non configurées"
fi

# 8. Installation des outils de monitoring GPU
log "Installation des outils de monitoring GPU..."
if ! command -v nvtop &> /dev/null; then
    apt update
    apt install -y nvtop
    success "Outil nvtop installé (utilisez 'nvtop' pour surveiller les GPUs)"
else
    log "nvtop est déjà installé"
fi

# 9. Création d'un service pour activer automatiquement tous les GPUs
log "Création d'un service pour activer automatiquement tous les GPUs au démarrage..."

cat > /etc/systemd/system/enable-all-gpus.service << EOF
[Unit]
Description=Enable all NVIDIA GPUs
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/enable-all-gpus.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable enable-all-gpus.service
success "Service enable-all-gpus créé et activé"

# 10. Récapitulatif
log "Optimisations terminées! Récapitulatif:"
echo "1. Configuration NVIDIA optimisée pour multi-GPU"
echo "2. Paramètres GRUB optimisés pour performances PCIe"
echo "3. Script de détection de tous les GPUs créé: /usr/local/bin/enable-all-gpus.sh"
echo "4. Paramètres système optimisés pour ML"
echo "5. Mode persistance NVIDIA activé"
echo "6. Limites de ressources système augmentées"
echo "7. Outils de monitoring GPU installés"
echo "8. Service d'activation automatique des GPUs créé"

echo -e "\n${YELLOW}IMPORTANT:${NC} Un redémarrage est nécessaire pour appliquer toutes les modifications."
echo -e "${YELLOW}Après le redémarrage:${NC} Vérifiez que tous les GPUs sont détectés avec 'nvidia-smi'"
echo -e "Si certains GPUs ne sont pas détectés, exécutez: ${GREEN}sudo /usr/local/bin/enable-all-gpus.sh${NC}"

read -p "Voulez-vous redémarrer maintenant? [y/N]: " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log "Redémarrage du système..."
    reboot
else
    warning "N'oubliez pas de redémarrer manuellement pour appliquer toutes les modifications!"
fi
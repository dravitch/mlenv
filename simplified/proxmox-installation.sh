#!/bin/bash
# Script d'installation de Proxmox VE sur Debian
# À exécuter sur un système Debian fraîchement installé

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

# Vérification que le système est Debian
if [ ! -f /etc/debian_version ]; then
    error "Ce script est conçu pour être exécuté sur Debian"
fi

log "Démarrage de l'installation de Proxmox VE..."

# Configuration du fichier hosts
log "Configuration du fichier hosts..."
HOSTNAME="predatorx"
IP_ADDRESS=$(ip route get 8.8.8.8 | awk '{print $7; exit}')

cat > /etc/hosts << EOF
127.0.0.1 localhost
${IP_ADDRESS} ${HOSTNAME}.local ${HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Définition du nom d'hôte
log "Définition du nom d'hôte..."
echo "${HOSTNAME}" > /etc/hostname
hostname "${HOSTNAME}"

# Mise à jour du système
log "Mise à jour du système..."
apt-get update && apt-get upgrade -y

# Installation des dépendances
log "Installation des dépendances..."
apt-get install -y sudo curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release

# Ajout du dépôt Proxmox VE
log "Ajout du dépôt Proxmox VE..."
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bullseye pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
wget -q -O- "http://download.proxmox.com/debian/proxmox-release-bullseye.gpg" | apt-key add -

# Mise à jour des paquets
log "Mise à jour des paquets avec le nouveau dépôt..."
apt-get update

# Installation de Proxmox VE
log "Installation de Proxmox VE (cela peut prendre un certain temps)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi

# Désactivation de l'interface pve-enterprise
log "Désactivation de l'interface pve-enterprise..."
echo "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Mise à jour après configuration
apt-get update

# Installation des outils de base
log "Installation des outils de base..."
apt-get install -y htop iotop iftop curl wget vim tmux qemu-guest-agent zfsutils-linux

# Configuration du service NTP
log "Configuration du service NTP..."
apt-get install -y chrony
systemctl enable chrony
systemctl start chrony

# Installation des outils GPU
log "Installation des outils pour GPU NVIDIA..."
apt-get install -y pve-headers-$(uname -r)
apt-get install -y build-essential gcc make
apt-get install -y nvidia-detect

# Détection des cartes NVIDIA
nvidia-detect > /tmp/nvidia-detect-output.txt
log "Résultat de la détection NVIDIA:"
cat /tmp/nvidia-detect-output.txt

# Message final
success "Installation de Proxmox VE terminée!"
log "Réboot nécessaire pour terminer la configuration."
log "Après le redémarrage, connectez-vous à l'interface web: https://${IP_ADDRESS}:8006"
log "Utilisateur: root"
log "Mot de passe: [votre mot de passe système]"

# Demande de redémarrage
read -p "Appuyez sur Entrée pour redémarrer le système..."
reboot
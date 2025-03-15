#!/bin/bash
# Script de post-installation pour Proxmox VE
# A exécuter après l'installation initiale

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
    error "Proxmox VE ne semble pas être installé. Ce script est destiné à une post-configuration."
fi

log "Démarrage de la configuration post-installation pour $(hostname)"

# 1. Configuration des dépôts
log "1. Configuration des dépôts Proxmox..."

# Ajout du dépôt no-subscription
if ! grep -q "pve-no-subscription" /etc/apt/sources.list; then
    cat >> /etc/apt/sources.list << EOF

# NON recommandé pour une utilisation en production
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF
    success "Dépôt no-subscription ajouté"
else
    log "Le dépôt no-subscription est déjà configuré"
fi

# Ajout du dépôt Ceph no-subscription
if ! grep -q "ceph-quincy" /etc/apt/sources.list; then
    cat >> /etc/apt/sources.list << EOF
# Pas pour Ceph de production
deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
EOF
    success "Dépôt Ceph no-subscription ajouté"
else
    log "Le dépôt Ceph no-subscription est déjà configuré"
fi

# Désactivation du dépôt enterprise
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list
    success "Dépôt enterprise désactivé"
fi

# Désactivation du dépôt Ceph enterprise
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/ceph.list
    success "Dépôt Ceph enterprise désactivé"
fi

# 2. Mise à jour du système
log "2. Mise à jour du système..."
apt-get update
apt-get upgrade -y
success "Paquets mis à jour avec succès"

# 3. Installation des outils utiles
log "3. Installation des outils utiles..."
apt-get install -y htop iotop iftop curl wget vim tmux qemu-guest-agent zfsutils-linux
success "Outils de base installés"

# 4. Désactivation de la fenêtre contextuelle d'abonnement
log "4. Désactivation de la fenêtre contextuelle d'abonnement..."

if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
    cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak
    sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    systemctl restart pveproxy.service
    success "Fenêtre contextuelle d'abonnement désactivée"
else
    warning "Fichier proxmoxlib.js non trouvé, impossible de désactiver la fenêtre contextuelle d'abonnement"
fi

# 5. Configuration des stockages locaux
log "5. Configuration des stockages locaux..."

STORAGE_PATH=${1:-"/mnt/vmstorage"}

if [ ! -d "$STORAGE_PATH" ]; then
    log "Création du répertoire de stockage $STORAGE_PATH..."
    mkdir -p "$STORAGE_PATH"/{images,containers,backups,iso}
    chmod 775 -R "$STORAGE_PATH"
    success "Répertoires de stockage créés"
else
    log "Le répertoire $STORAGE_PATH existe déjà"
fi

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

success "Stockages configurés"

# 6. Téléchargement des templates LXC
log "6. Téléchargement des templates LXC..."
pveam update

# Vérifier si le template Debian 12 est déjà téléchargé
if ! pveam list local | grep -q "debian-12-standard"; then
    log "Téléchargement du template Debian 12..."
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst
    success "Template Debian 12 téléchargé"
else
    log "Le template Debian 12 est déjà téléchargé"
fi

# 7. Configuration du pare-feu
log "7. Configuration du pare-feu..."

# Créer le répertoire de configuration du pare-feu s'il n'existe pas
if [ ! -d /etc/pve/firewall ]; then
    mkdir -p /etc/pve/firewall
fi

# Configurer le pare-feu cluster
cat > /etc/pve/firewall/cluster.fw << EOF
[OPTIONS]
enable: 1

[RULES]
IN SSH(ACCEPT) -i vmbr0
IN ACCEPT -i vmbr0 -p tcp -dport 8006
IN ACCEPT -i vmbr0 -p tcp -dport 80
IN ACCEPT -i vmbr0 -p tcp -dport 443
EOF

success "Configuration du pare-feu terminée"

# 8. Configuration du service NTP
log "8. Configuration du service NTP..."
apt-get install -y chrony
systemctl enable chrony
systemctl start chrony
success "Service NTP (chrony) configuré"

# 9. Création du script de sauvegarde automatique
log "9. Création du script de sauvegarde automatique..."

mkdir -p /var/log/pve-backup
cat > /usr/local/bin/pve-backup.sh << 'EOF'
#!/bin/bash
# Script de sauvegarde automatique Proxmox
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/mnt/vmstorage/backups"
LOG_FILE="/var/log/pve-backup/backup-${DATE}.log"

echo "Démarrage des sauvegardes: $(date)" | tee -a "$LOG_FILE"

# Sauvegarde des VMs
for VM_ID in $(qm list | tail -n+2 | awk '{print $1}')
do
    echo "Sauvegarde de la VM $VM_ID..." | tee -a "$LOG_FILE"
    vzdump $VM_ID --compress zstd --mode snapshot --storage backup | tee -a "$LOG_FILE"
done

# Sauvegarde des conteneurs
for CT_ID in $(pct list | tail -n+2 | awk '{print $1}')
do
    echo "Sauvegarde du conteneur $CT_ID..." | tee -a "$LOG_FILE"
    vzdump $CT_ID --compress zstd --mode snapshot --storage backup | tee -a "$LOG_FILE"
done

# Conservation des 7 derniers jours de logs uniquement
find /var/log/pve-backup -name "backup-*.log" -mtime +7 -delete

echo "Sauvegardes terminées: $(date)" | tee -a "$LOG_FILE"
EOF

chmod +x /usr/local/bin/pve-backup.sh

# Ajout d'une tâche cron pour la sauvegarde quotidienne à 1h du matin
(crontab -l 2>/dev/null || echo "") | grep -v "pve-backup.sh" | { cat; echo "0 1 * * * /usr/local/bin/pve-backup.sh"; } | crontab -
success "Script de sauvegarde configuré"

# 10. Résumé de la configuration
log "Configuration post-installation terminée!"
log "Récapitulatif:"
log "- Dépôts community configurés"
log "- Système mis à jour"
log "- Outils de base installés"
log "- Stockages configurés (vm-storage, ct-storage, backup, iso)"
log "- Template Debian 12 téléchargé"
log "- Pare-feu configuré"
log "- Service NTP configuré"
log "- Script de sauvegarde automatique configuré"

log "Vous pouvez maintenant accéder à l'interface web Proxmox sur:"
log "https://$(hostname -I | awk '{print $1}'):8006"

# Suggérer la prochaine étape
echo
echo -e "${GREEN}=== Prochaines étapes ===${NC}"
echo "1. Configurez le passthrough GPU si nécessaire: ./progressive-gpu-passthrough.sh"
echo "2. Configurez le stockage M.2 si disponible: ../storage/setup-m2-storage.sh"
echo "3. Déployez les VMs et conteneurs: cd ../ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml"
echo

read -p "Voulez-vous redémarrer maintenant pour appliquer toutes les modifications? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    log "Redémarrage du système..."
    reboot
else
    log "N'oubliez pas de redémarrer manuellement si nécessaire."
fi
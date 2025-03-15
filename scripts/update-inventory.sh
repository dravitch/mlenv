#!/bin/bash
# Script pour mettre à jour l'inventaire Ansible en utilisant les variables du fichier .env
# À exécuter depuis la racine du projet MLENV

# Couleurs pour les messages
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'  # No Color

# Fonction d'affichage des messages
log_message() {
    local MESSAGE=$1
    local TYPE=${2:-"Info"}

    case $TYPE in
        "Info") COLOR=$BLUE ;;
        "Success") COLOR=$GREEN ;;
        "Warning") COLOR=$YELLOW ;;
        "Error") COLOR=$RED ;;
        *) COLOR=$NC ;;
    esac

    echo -e "${COLOR}[$(date '+%Y-%m-%d %H:%M:%S')] [$TYPE] $MESSAGE${NC}"
}

# Vérifier si le fichier .env existe
if [ ! -f ".env" ]; then
    log_message "Le fichier .env n'existe pas. Création à partir de .env.example..." "Warning"
    if [ -f ".env.example" ]; then
        cp .env.example .env
        log_message "Fichier .env créé. Veuillez le modifier avec vos valeurs personnalisées puis réexécuter ce script." "Warning"
    else
        log_message "Fichier .env.example introuvable. Impossible de créer .env." "Error"
        exit 1
    fi
    exit 0
fi

# Charger les variables d'environnement depuis le fichier .env
log_message "Chargement des variables depuis .env..."
while IFS='=' read -r KEY VALUE || [ -n "$KEY" ]; do
    # Ignorer les lignes vides ou les commentaires
    if [[ -z "$KEY" || "$KEY" == \#* ]]; then
        continue
    fi

    # Supprimer les espaces en début et fin de KEY
    KEY=$(echo "$KEY" | xargs)

    # Exporter les variables d'environnement
    export "$KEY"="$VALUE"
done < .env

# Vérifier si le répertoire ansible/inventory existe
if [ ! -d "ansible/inventory" ]; then
    mkdir -p ansible/inventory
    log_message "Répertoire ansible/inventory créé." "Info"
fi

# Vérifier si le répertoire ansible/inventory/group_vars existe
if [ ! -d "ansible/inventory/group_vars" ]; then
    mkdir -p ansible/inventory/group_vars
    log_message "Répertoire ansible/inventory/group_vars créé." "Info"
fi

# Mettre à jour le fichier hosts.yml
log_message "Mise à jour du fichier hosts.yml..."
cat > ansible/inventory/hosts.yml << EOF
---
all:
  children:
    proxmox:
      hosts:
        predatorx:
          ansible_connection: local
          backtesting_vm_id: ${MLENV_BACKTESTING_VM_ID:-100}
          ml_vm_id: ${MLENV_ML_VM_ID:-101}
          webserver_vm_id: ${MLENV_WEB_VM_ID:-102}
          db_container_id: ${MLENV_DB_CT_ID:-200}
          backup_container_id: ${MLENV_BACKUP_CT_ID:-201}
          proxmox_host: "${MLENV_HOST_IP:-192.168.1.100}"
          proxmox_user: "${MLENV_SSH_USER:-root@pam}"
          proxmox_password: "${MLENV_DEFAULT_PASSWORD:-your_proxmox_password}"
          proxmox_target: "pve"
          bridge_interface: ${MLENV_BRIDGE_INTERFACE:-vmbr0}
      vars:
        vm_memory: ${MLENV_VM_MEMORY:-4096}
        vm_cores: ${MLENV_VM_CORES:-4}
        vm_disk_size: "${MLENV_VM_DISK_SIZE:-60G}"
        vm_iso_image: "local:iso/ubuntu-22.04.4-live-server-amd64.iso"
        backtesting_gpu_indices: [${MLENV_BACKTESTING_GPU_INDICES:-0}]
        ml_gpu_indices: [${MLENV_ML_GPU_INDICES:-1,2,3,4,5,6,7}]
        start_vm_after_creation: false
        configure_vm_environments: false
        create_web_server: false

backtesting:
  hosts:
    predatorx:
      vm_id: "{{ hostvars['predatorx']['backtesting_vm_id'] }}"

machine_learning:
  hosts:
    predatorx:
      vm_id: "{{ hostvars['predatorx']['ml_vm_id'] }}"

webserver:
  hosts:
    predatorx:
      vm_id: "{{ hostvars['predatorx']['webserver_vm_id'] }}"
      when: create_web_server | default(false) | bool

containers:
  hosts:
    predatorx:
      db_id: "{{ hostvars['predatorx']['db_container_id'] }}"
      backup_id: "{{ hostvars['predatorx']['backup_container_id'] }}"
EOF

# Mettre à jour le fichier all.yml
log_message "Mise à jour du fichier group_vars/all.yml..."
cat > ansible/inventory/group_vars/all.yml << EOF
---
# Variables globales pour tous les hôtes
# Ces variables peuvent être remplacées au niveau du groupe ou de l'hôte

# Configuration de stockage
storage_path: "${MLENV_STORAGE_PATH:-/mnt/vmstorage}"
backup_path: "${MLENV_BACKUP_PATH:-/mnt/vmstorage/backups}"
external_disk: "${MLENV_EXTERNAL_DISK:-/dev/sdX1}"

# Configuration GPU
gpu_ids: "${MLENV_GPU_IDS:-10de:2184,10de:1e84}"
backtesting_gpu_indices: [${MLENV_BACKTESTING_GPU_INDICES:-0}]
ml_gpu_indices: [${MLENV_ML_GPU_INDICES:-1,2,3,4,5,6,7}]

# Configuration des VMs
vm_memory: ${MLENV_VM_MEMORY:-4096}
vm_cores: ${MLENV_VM_CORES:-2}
vm_disk_size: "${MLENV_VM_DISK_SIZE:-40G}"
vm_iso_image: "local:iso/ubuntu-22.04.4-live-server-amd64.iso"

# Configuration des conteneurs
ct_memory: ${MLENV_CT_MEMORY:-1024}
ct_cores: ${MLENV_CT_CORES:-1}

# Configuration des utilisateurs
backtesting_user: "${MLENV_BACKTESTING_USER:-backtester}"
ml_user: "${MLENV_ML_USER:-aitrader}"
default_password: "${MLENV_DEFAULT_PASSWORD:-changeme}"

# Configuration Jupyter
jupyter_port: ${MLENV_JUPYTER_PORT:-8888}
jupyter_password_hash: "${MLENV_JUPYTER_PASSWORD_HASH:-sha1:74ba40f8a388:c913541b7ee99d15d5ed31d4226bf7838f83a50e}"

# Configuration PostgreSQL
db_name: "${MLENV_DB_NAME:-tradingdb}"
db_user: "${MLENV_DB_USER:-trading}"
db_password: "${MLENV_DB_PASSWORD:-secure_password}"

# Configuration réseau
bridge_interface: "${MLENV_BRIDGE_INTERFACE:-vmbr0}"
use_vlan: ${MLENV_USE_VLAN:-false}
vlan_id: ${MLENV_VLAN_ID:-100}

# Options avancées
iommu_type: "${MLENV_IOMMU_TYPE:-intel}"
debug_mode: ${MLENV_DEBUG_MODE:-false}

# Déploiement
start_vm_after_creation: false
configure_vm_environments: false
create_web_server: false
EOF

log_message "Inventaire Ansible mis à jour avec succès!" "Success"
log_message "Vous pouvez maintenant exécuter les playbooks Ansible avec la commande:" "Info"
log_message "  cd ansible && ansible-playbook playbooks/site.yml" "Info"

# Rendre le script exécutable
chmod +x "$0"
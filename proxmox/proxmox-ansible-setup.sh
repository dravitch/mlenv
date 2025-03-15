#!/bin/bash

# Installation d'Ansible et Git sur Proxmox
echo "Mise à jour des paquets et installation d'Ansible et Git..."
apt update && apt install -y ansible git

# Clonage du repository (avec authentification si nécessaire)
echo "Clonage du dépôt mlenv..."
git clone https://github.com/votre-username/mlenv.git
if [ $? -ne 0 ]; then
  echo "Erreur lors du clonage du dépôt. Vérifiez l'URL et l'authentification."
  exit 1
fi

cd mlenv

# Modification de l'inventaire pour localhost
echo "Modification de l'inventaire hosts.yml..."
cat > ansible/inventory/hosts.yml << EOF
all:
  children:
    proxmox:
      hosts:
        predatorx:
          ansible_connection: local
          backtesting_vm_id: 100
          ml_vm_id: 101
          webserver_vm_id: 102
          db_container_id: 200
          backup_container_id: 201
EOF

# Création du répertoire group_vars
mkdir -p ansible/inventory/group_vars

# Modification des variables globales pour refléter le nouvel emplacement de stockage
echo "Modification des variables globales all.yml..."
cat > ansible/inventory/group_vars/all.yml << EOF
---
# Variables globales pour tous les hôtes

# Configuration Proxmox
proxmox:
  storage_path: /mnt/vmstorage
  templates_storage: "local"
  vm_storage: "vm-storage"
  ct_storage: "ct-storage"
  backup_storage: "backup"
  iso_storage: "iso"

# Configuration réseau
network:
  bridge: vmbr0
  vlan_aware: true

# Configuration GPU
gpu:
  enable_passthrough: true
  primary_gpu_id: "01:00.0"  # À adapter selon votre configuration
  all_gpus: true  # Passer tous les GPUs disponibles à la VM principale

# Configuration des VMs
vms:
  backtesting:
    id: 100
    name: "BacktestingGPU"
    memory: 16384  # 16 Go
    cores: 2
    disk_size: "40G"
    os_type: "ubuntu"
    iso: "ubuntu-22.04.4-live-server-amd64.iso"
    username: "backtester"
    password: "backtester"  # À modifier pour la production

  ml:
    id: 101
    name: "MachineLearning"
    memory: 16384  # 16 Go
    cores: 2
    disk_size: "100G"
    os_type: "ubuntu"
    iso: "ubuntu-22.04.4-live-server-amd64.iso"
    username: "aitrader"
    password: "aitrader"  # À modifier pour la production

# Configuration des conteneurs
containers:
  db:
    id: 200
    hostname: "db-server"
    memory: 2048
    cores: 1
    disk_size: "20G"
    template: "debian-12-standard_12.7-1_amd64.tar.zst"

  backup:
    id: 201
    hostname: "backup-server"
    memory: 2048
    cores: 1
    disk_size: "20G"
    template: "debian-12-standard_12.7-1_amd64.tar.zst"
EOF

# Exécution du playbook proxmox-setup pour finaliser la configuration
echo "Exécution du playbook Ansible proxmox-setup.yml..."
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/proxmox-setup.yml
if [ $? -ne 0 ]; then
  echo "Erreur lors de l'exécution du playbook Ansible."
  exit 1
fi

echo "Configuration terminée."
# Plan de Reprise d'Activité pour l'Infrastructure Proxmox

Ce document détaille les étapes à suivre pour reconstituer l'infrastructure MLENV sur Proxmox à partir du dépôt Git, que ce soit suite à une panne, une réinitialisation ou une nouvelle installation.

## Table des matières

1. [Préparation](#1-préparation)
2. [Installation de Proxmox VE](#2-installation-de-proxmox-ve)
3. [Configuration de base de Proxmox](#3-configuration-de-base-de-proxmox)
4. [Configuration du GPU Passthrough](#4-configuration-du-gpu-passthrough)
5. [Déploiement via Ansible](#5-déploiement-via-ansible)
6. [Configuration manuelle (si nécessaire)](#6-configuration-manuelle-si-nécessaire)
7. [Vérification et validation](#7-vérification-et-validation)
8. [Restauration des données](#8-restauration-des-données)
9. [Problèmes courants et solutions](#9-problèmes-courants-et-solutions)

## 1. Préparation

### 1.1 Clonage du dépôt sur une machine de travail

```bash
# Cloner le dépôt
git clone https://github.com/votre-username/mlenv.git
cd mlenv

# Si vous avez des informations de configuration personnalisées:
cp /chemin/vers/sauvegarde/.env .env
```

### 1.2 Matériel requis

- Serveur physique avec CPU Intel/AMD supportant la virtualisation
- Cartes GPU NVIDIA installées
- Média d'installation Proxmox VE 8.x (USB)
- Réseau configuré avec accès internet

## 2. Installation de Proxmox VE

### 2.1 Installation standard

1. Démarrez sur le média d'installation Proxmox VE
2. Suivez l'assistant d'installation avec les paramètres recommandés:
   - Disque de destination: SSD système
   - Nom d'hôte: `predatorx` (ou votre nom personnalisé)
   - Configuration réseau selon votre environnement
   - Mot de passe root sécurisé

### 2.2 Vérifications post-installation

```bash
# Vérifier la version de Proxmox
pveversion

# Vérifier l'état du système
systemctl status pve-cluster

# Vérifier la connectivité réseau
ping -c 4 8.8.8.8
```

## 3. Configuration de base de Proxmox

### 3.1 Accès au serveur

```bash
# Se connecter en SSH au serveur Proxmox
ssh root@IP-DU-SERVEUR

# Cloner le dépôt MLENV
apt update && apt install -y git
git clone https://github.com/votre-username/mlenv.git /root/mlenv
cd /root/mlenv
```

### 3.2 Configuration post-installation

```bash
# Exécuter le script de configuration post-installation
bash proxmox/post-install.sh

# Vérifier les résultats
pvesm status
cat /etc/apt/sources.list.d/pve-no-subscription.list
```

### 3.3 Configuration du stockage

```bash
# Si vous utilisez un disque M.2 ou un stockage additionnel:
bash storage/setup-m2-storage.sh

# Ou configurez manuellement le stockage:
mkdir -p /mnt/vmstorage/{images,containers,backups,iso}
pvesm add dir vm-storage --path /mnt/vmstorage/images --content images,rootdir
pvesm add dir ct-storage --path /mnt/vmstorage/containers --content rootdir
pvesm add dir backup --path /mnt/vmstorage/backups --content backup
pvesm add dir iso --path /mnt/vmstorage/iso --content iso
```

## 4. Configuration du GPU Passthrough

### 4.1 Identification des GPU

```bash
# Identifier les cartes GPU et leurs IDs
lspci -nn | grep -i nvidia

# Noter les IDs, par exemple:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:2184] (rev a1)
```

### 4.2 Configuration IOMMU et VFIO

```bash
# Configuration du GPU Passthrough via le script
bash proxmox/progressive-gpu-passthrough.sh

# Suivre les instructions à l'écran
# Après redémarrage, vérifier:
lspci -nnk | grep -i nvidia -A3
```

### 4.3 Résolution de problèmes de Passthrough

Si le passthrough ne fonctionne pas après le redémarrage:

```bash
# Vérifier l'activation IOMMU
dmesg | grep -i iommu

# Vérifier les groupes IOMMU
find /sys/kernel/iommu_groups/ -type l | sort -V | while read -r iommu; do echo "IOMMU Group $(basename "$(dirname "$iommu")"):"; ls -l "$iommu"; done

# Vérifier les modules VFIO chargés
lsmod | grep vfio
```

## 5. Déploiement via Ansible

### 5.1 Installation d'Ansible

Si vous utilisez une machine Linux/macOS pour gérer le déploiement:

```bash
# Sur Debian/Ubuntu:
apt update && apt install -y ansible

# Sur macOS:
brew install ansible
```

Si vous utilisez Windows:

```powershell
# Via pip dans WSL ou environnement Python:
pip install ansible
```

### 5.2 Configuration des fichiers d'inventaire

```bash
# Assurez-vous que votre fichier .env est configuré
./scripts/Apply-Configuration.ps1  # Windows
bash scripts/apply-configuration.sh  # Linux/macOS

# Vérifiez les fichiers générés
cat ansible/inventory/hosts.yml
cat ansible/inventory/group_vars/all.yml
```

### 5.3 Exécution des playbooks Ansible

```bash
# Exécuter le playbook complet
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Ou exécuter des parties spécifiques:
ansible-playbook -i inventory/hosts.yml playbooks/proxmox-setup.yml
ansible-playbook -i inventory/hosts.yml playbooks/backtesting-vm.yml
ansible-playbook -i inventory/hosts.yml playbooks/ml-vm.yml
ansible-playbook -i inventory/hosts.yml playbooks/container-setup.yml
```

## 6. Configuration manuelle (si nécessaire)

Si certaines étapes échouent ou ne peuvent pas être automatisées:

### 6.1 Création manuelle des VMs

Via l'interface web Proxmox (https://IP-DU-SERVEUR:8006):

1. Créer VM > Général:
   - Nom: BacktestingGPU
   - ID VM: 100
   - Système d'exploitation: Linux 6.x - 2.6 Kernel

2. Processeur:
   - Sockets: 1
   - Cœurs: 2 (selon votre CPU)
   - Type: host

3. Mémoire:
   - 8192 Mo (ou selon vos besoins)

4. Disque:
   - Bus/Périphérique: SATA
   - Stockage: vm-storage
   - Taille du disque: 40 Go

5. Réseau:
   - Model: VirtIO
   - Bridge: vmbr0

6. Confirmer et terminer

7. Après création, modifier les options:
   - Système > Bios: OVMF (UEFI)
   - Machine: q35
   - Options > arguments: `-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'`

### 6.2 Configuration manuelle du passthrough GPU

```bash
# Arrêter la VM
qm stop 100

# Ajouter le GPU (remplacer XX:XX.X par l'ID PCI réel)
qm set 100 --hostpci0 XX:XX.X,pcie=1,x-vga=on

# Démarrer la VM
qm start 100
```

### 6.3 Installation du système d'exploitation dans les VMs

1. Via la console Proxmox, installer Ubuntu 22.04 Server ou Debian 12
2. Après installation, installer les pilotes NVIDIA:

```bash
# Dans la VM:
sudo apt update && sudo apt install -y build-essential gcc g++ make
sudo apt install -y nvidia-driver-550 nvidia-utils-550
sudo reboot
```

## 7. Vérification et validation

### 7.1 Vérification des VMs

```bash
# Liste des VMs
qm list

# Statut des VMs
qm status 100
qm status 101
```

### 7.2 Vérification des conteneurs

```bash
# Liste des conteneurs
pct list

# Statut des conteneurs
pct status 200
pct status 201
```

### 7.3 Vérification du passthrough GPU

Se connecter aux VMs et vérifier:

```bash
# Vérifier les GPUs dans la VM
nvidia-smi

# Vérifier les capacités CUDA
nvcc --version
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.cuda.device_count())"
```

## 8. Restauration des données

### 8.1 Restauration depuis une sauvegarde

Si vous avez des sauvegardes Proxmox:

```bash
# Lister les sauvegardes disponibles
ls -la /mnt/vmstorage/backups/

# Restaurer une VM
qmrestore /mnt/vmstorage/backups/vzdump-qemu-100-YYYY_MM_DD-HH_MM_SS.vma.zst 100 --storage vm-storage

# Restaurer un conteneur
pct restore 200 /mnt/vmstorage/backups/vzdump-lxc-200-YYYY_MM_DD-HH_MM_SS.tar.zst --storage ct-storage
```

### 8.2 Restauration des données utilisateur

Pour les données Jupyter et projets:

```bash
# Restaurer les données utilisateur dans la VM
scp -r /chemin/vers/sauvegarde/projects user@IP-VM:~/projects
```

### 8.3 Restauration de la base de données

```bash
# Restaurer PostgreSQL
cat /chemin/vers/sauvegarde/database.sql | pct exec 200 -- psql -U postgres
```

## 9. Problèmes courants et solutions

### 9.1 Problèmes d'accès à l'interface Web Proxmox

- **Problème**: Interface web inaccessible
- **Solution**: Vérifier le service `pveproxy`
  ```bash
  systemctl status pveproxy
  systemctl restart pveproxy
  ```

### 9.2 Problèmes de passthrough GPU

- **Problème**: GPUs non détectés dans la VM
- **Solutions**:
  1. Vérifier IOMMU activé dans BIOS
  2. Utiliser `x-vga=on` pour au moins une carte
  3. Vérifier les arguments CPU (vendor_id et kvm=off)

### 9.3 La VM ne démarre pas après ajout du GPU

- **Problème**: Écran noir ou erreur au démarrage
- **Solutions**:
  1. Commencer avec une seule carte GPU
  2. Vérifier les logs:
     ```bash
     qm showcmd 100  # Voir la commande QEMU
     tail -f /var/log/pve/qemu-server/100.log
     ```

### 9.4 Erreur 43 NVIDIA

- **Problème**: GPU détecté mais erreur 43 dans la VM
- **Solution**:
  ```bash
  qm set 100 --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"
  ```

---

Pour toute assistance supplémentaire:

- Consultez la documentation Proxmox: [https://pve.proxmox.com/wiki/](https://pve.proxmox.com/wiki/)
- Guide sur le passthrough GPU: [https://pve.proxmox.com/wiki/PCI_Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)
- Ouvrez une issue sur le dépôt GitHub du projet
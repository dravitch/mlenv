# Procédure de réinitialisation de l'environnement MLENV

Ce document détaille les étapes pour réinitialiser complètement l'environnement MLENV, que ce soit pour le développement local ou pour l'infrastructure Proxmox.

## 1. Réinitialisation de l'environnement Git local (Windows 11)

### 1.1 Sauvegarde des fichiers importants (si nécessaire)

```powershell
# Créer un répertoire de sauvegarde
$BackupDir = "C:\Path\To\MLENV_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $BackupDir -ItemType Directory -Force

# Copier les fichiers importants non versionnés
Copy-Item -Path "C:\Path\To\MLENV\.env" -Destination $BackupDir -ErrorAction SilentlyContinue
Copy-Item -Path "C:\Path\To\MLENV\custom_configs\*" -Destination "$BackupDir\custom_configs\" -Recurse -ErrorAction SilentlyContinue
```

### 1.2 Suppression du dépôt Git local

```powershell
# Se déplacer à l'extérieur du répertoire
cd ..

# Option 1: Suppression simple du répertoire Git
Remove-Item -Path "MLENV" -Recurse -Force

# Option 2: Conservation du répertoire, mais réinitialisation Git
cd MLENV
Remove-Item -Path ".git" -Recurse -Force
```

### 1.3 Réinitialisation du dépôt à partir de GitHub

```powershell
# Cloner à nouveau le dépôt depuis GitHub
git clone https://github.com/votre-username/mlenv.git MLENV_Fresh

# Si vous avez supprimé le répertoire original:
cd MLENV_Fresh

# Si vous avez conservé le répertoire mais supprimé .git:
cd ..
git clone https://github.com/votre-username/mlenv.git MLENV_Temp
Copy-Item -Path "MLENV_Temp/.git" -Destination "MLENV" -Recurse
Remove-Item -Path "MLENV_Temp" -Recurse -Force
cd MLENV
git reset --hard HEAD
```

### 1.4 Restauration des fichiers personnalisés

```powershell
# Restaurer les fichiers personnalisés si nécessaire
if (Test-Path "$BackupDir\.env") {
    Copy-Item -Path "$BackupDir\.env" -Destination "."
}

if (Test-Path "$BackupDir\custom_configs") {
    Copy-Item -Path "$BackupDir\custom_configs\*" -Destination ".\custom_configs\" -Recurse
}
```

## 2. Régénération de la structure du projet

### 2.1 Utilisation du script PowerShell

```powershell
# Exécuter le script de création de structure
.\Create-ProjectStructure.ps1
```

### 2.2 Vérification de la structure

```powershell
# Vérifier que tous les répertoires et fichiers ont été créés correctement
Get-ChildItem -Recurse | Measure-Object | Select-Object -ExpandProperty Count
```

## 3. Réinitialisation de l'environnement Proxmox

Cette section s'applique si vous devez également réinitialiser l'infrastructure Proxmox.

### 3.1 Sauvegarde des configurations Proxmox

Avant toute réinitialisation, effectuez ces sauvegardes sur l'hôte Proxmox:

```bash
# Sauvegarde des configurations importantes
mkdir -p /root/pve_backup
cp -r /etc/pve /root/pve_backup/
qm list > /root/pve_backup/vm_list.txt
for vmid in $(qm list | tail -n+2 | awk '{print $1}'); do
    qm config $vmid > /root/pve_backup/vm${vmid}_config.txt
done
```

### 3.2 Option douce: Réinitialisation des configurations défectueuses uniquement

Pour réinitialiser uniquement les configurations problématiques:

```bash
# Désactivation des configurations de passthrough GPU problématiques
mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.bak
mv /etc/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf.bak
update-initramfs -u -k all
```

### 3.3 Option radicale: Réinstallation de Proxmox

Si une réinstallation complète est nécessaire:

1. Sauvegardez toutes les VMs et conteneurs:
   ```bash
   mkdir -p /mnt/backup
   for vmid in $(qm list | tail -n+2 | awk '{print $1}'); do
       vzdump $vmid --compress zstd --mode snapshot --dumpdir /mnt/backup
   done
   ```

2. Notez la configuration réseau et les détails de stockage:
   ```bash
   ip addr show > /root/pve_backup/network_config.txt
   pvesm status > /root/pve_backup/storage_config.txt
   ```

3. Réinstallez Proxmox VE via l'ISO

4. Après réinstallation, appliquez la configuration de base:
   ```bash
   bash /path/to/cloned/repo/proxmox/post-install.sh
   ```

5. Restaurez les VMs et conteneurs:
   ```bash
   # Pour chaque sauvegarde
   qmrestore /mnt/backup/vzdump-qemu-XXX.vma.zst NEW_VMID --storage STORAGE_NAME
   ```

### 3.4 Application des configurations via Ansible

Une fois Proxmox réinitialisé, vous pouvez appliquer les configurations via Ansible:

```bash
# Sur la machine contrôlant Ansible
cd /path/to/mlenv/ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## 4. Vérification et validation

### 4.1 Vérifications Git

```powershell
# Vérifier l'état du dépôt
git status
git remote -v
git log --oneline -n 5
```

### 4.2 Vérifications Proxmox

```bash
# Vérifier que toutes les VMs sont disponibles
qm list

# Vérifier les configurations GPU
lspci -nnk | grep -i nvidia
cat /etc/modprobe.d/vfio.conf

# Vérifier les stockages
pvesm status
```

### 4.3 Test des VMs et services

1. Démarrez les VMs principales:
   ```bash
   qm start 100  # VM Backtesting
   qm start 101  # VM Machine Learning
   ```

2. Vérifiez l'accès Jupyter:
   - Ouvrez un navigateur et accédez à `http://IP-VM-BACKTESTING:8888`
   - Vérifiez `http://IP-VM-ML:8888`

3. Testez la détection GPU dans les VMs:
   ```bash
   # Se connecter en SSH puis:
   nvidia-smi
   ```

## 5. Résolution des problèmes courants

### 5.1 Problèmes de clonage Git

- **Erreur d'authentification**: Vérifiez vos identifiants GitHub ou utilisez SSH
- **Dépôt corrompu**: Supprimez complètement et recommencez le clonage

### 5.2 Problèmes de passthrough GPU

- **GPUs non détectés**: Vérifiez que l'IOMMU est activé dans le BIOS et GRUB
- **VM ne démarre pas**: Essayez de démarrer avec un seul GPU d'abord
- **Erreur 43 NVIDIA**: Assurez-vous que les paramètres `vendor_id` et `kvm=off` sont configurés

### 5.3 Problèmes de VMs

- **Impossible de créer/démarrer VM**: Vérifiez les logs Proxmox dans `/var/log/pve/`
- **Pas d'accès réseau**: Vérifiez la configuration réseau des VMs et de l'hôte

### 5.4 Erreurs Ansible

- **Timeout de connexion**: Vérifiez les pare-feu et la connectivité SSH
- **Erreurs de permission**: Vérifiez les droits sudo et les fichiers de configuration

## 6. Contact et support

Pour toute assistance supplémentaire:
- Ouvrez une issue sur le dépôt GitHub
- Consultez la documentation détaillée dans le répertoire `doc/`

# Documentation mise à jour : Installation des GPUs NVIDIA sur Debian sous Proxmox

## Configuration correcte du passthrough GPU pour Debian

La configuration du passthrough GPU pour Debian sous Proxmox nécessite une séquence d'étapes précise. Voici la procédure complète et optimisée qui a permis de faire fonctionner les 8 cartes NVIDIA GTX 1660 Super/Ti.

### 1. Préparation de l'hôte Proxmox

```bash
# Activation de l'IOMMU sur l'hôte
echo "options vfio-pci ids=10de:21c4,10de:1aeb,10de:1aec,10de:1aed,10de:2182" > /etc/modprobe.d/vfio.conf
echo "vfio-pci" >> /etc/modules
update-initramfs -u
```

### 2. Séquence correcte de création et configuration de la VM

```bash
# Créer la VM de base
qm create 100 --name "BacktestingGPU" --memory 8192 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Ajouter le disque EFI
qm set 100 --efidisk0 local-lvm:1

# Ajouter le disque principal (SATA pour meilleure compatibilité)
qm set 100 --sata0 local-lvm:40,ssd=1

# Ajouter un lecteur CD avec l'ISO Debian
qm set 100 --ide2 local:iso/debian-12.5.0-amd64-netinst.iso,media=cdrom

# Configurer les paramètres CPU avancés
qm set 100 --args "-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'"

# Redémarrer la VM après l'installation du système d'exploitation
qm stop 100
qm start 100

# Configurer le passthrough GPU (à exécuter APRÈS l'installation du système)
qm stop 100

# Configurer la première carte avec x-vga=on
qm set 100 --delete hostpci0
qm set 100 --hostpci0 01:00.0,pcie=1,x-vga=on

# Ajouter les autres cartes
qm set 100 --hostpci1 02:00.0,pcie=1
qm set 100 --hostpci2 03:00.0,pcie=1
qm set 100 --hostpci3 04:00.0,pcie=1
qm set 100 --hostpci4 06:00.0,pcie=1
qm set 100 --hostpci5 07:00.0,pcie=1
qm set 100 --hostpci6 08:00.0,pcie=1
qm set 100 --hostpci7 09:00.0,pcie=1

# Démarrer la VM
qm start 100
```

### 3. Script d'installation des pilotes NVIDIA sur Debian

```bash
#!/bin/bash
# Script d'installation pour les pilotes NVIDIA sur Debian 12
# À exécuter après l'installation du système

set -e  # Arrêter le script en cas d'erreur

# Fonction d'affichage des messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root" >&2
    exit 1
fi

# Mise à jour du système
log "Mise à jour du système..."
apt-get update && apt-get upgrade -y

# Installation des outils de base
log "Installation des outils de base..."
apt-get install -y build-essential gcc g++ make cmake unzip git curl wget htop nano screen tmux sudo

# Ajout du dépôt non-free pour les pilotes NVIDIA
log "Configuration des dépôts pour les pilotes NVIDIA..."
apt-get install -y software-properties-common
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt-get update

# Installation des en-têtes kernel
log "Installation des en-têtes kernel..."
apt-get install -y linux-headers-$(uname -r) linux-headers-amd64

# Blacklister le pilote Nouveau
log "Blacklist du pilote Nouveau..."
cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF
update-initramfs -u

# Téléchargement et installation du pilote NVIDIA
log "Téléchargement du pilote NVIDIA..."
cd /tmp
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.54.14/NVIDIA-Linux-x86_64-550.54.14.run
chmod +x NVIDIA-Linux-x86_64-550.54.14.run

log "Installation des pilotes NVIDIA..."
./NVIDIA-Linux-x86_64-550.54.14.run --silent --disable-nouveau

# Vérification de l'installation NVIDIA
log "Vérification de l'installation NVIDIA..."
nvidia-smi || log "Erreur lors de la détection GPU NVIDIA - redémarrage peut-être nécessaire"

# Installation de CUDA
log "Installation de CUDA..."
apt-get install -y nvidia-cuda-toolkit

# Installation de Python et des librairies nécessaires
log "Installation de Python et des librairies de backtesting..."
apt-get install -y python3-pip python3-dev python3-venv

# Création d'un utilisateur pour le backtesting
log "Création d'un utilisateur pour le backtesting..."
useradd -m -s /bin/bash backtester
echo "backtester:backtester" | chpasswd
usermod -aG sudo backtester

# Création d'un environnement Python dédié
su - backtester -c "python3 -m venv ~/venv"

# Installation des librairies Python pour le backtesting
su - backtester -c "
source ~/venv/bin/activate && 
pip install --upgrade pip && 
pip install numpy pandas scipy matplotlib seaborn scikit-learn statsmodels pytables jupyterlab ipykernel ipywidgets &&
pip install pyfolio backtrader vectorbt yfinance alpha_vantage ta ccxt &&
pip install dash plotly &&
pip install psycopg2-binary SQLAlchemy &&
pip install tensorflow &&
pip install torch torchvision torchaudio
"

# Configuration de Jupyter
log "Configuration de Jupyter..."
su - backtester -c "
source ~/venv/bin/activate &&
jupyter notebook --generate-config
"

# Configuration pour accès à distance
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.password = ''
EOF

# Configuration du service systemd pour Jupyter
cat > /etc/systemd/system/jupyter.service << EOF
[Unit]
Description=Jupyter Notebook Server
After=network.target

[Service]
Type=simple
User=backtester
ExecStart=/home/backtester/venv/bin/jupyter lab --config=/etc/jupyter/jupyter_notebook_config.py
WorkingDirectory=/home/backtester
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Activation et démarrage du service
systemctl enable jupyter.service
systemctl start jupyter.service

# Configuration du pare-feu
log "Configuration du pare-feu..."
apt-get install -y ufw
ufw allow ssh
ufw allow 8888/tcp  # Port Jupyter
ufw --force enable

# Création des répertoires de projet
log "Création des répertoires de projet..."
su - backtester -c "
mkdir -p ~/projects/data
mkdir -p ~/projects/strategies
mkdir -p ~/projects/results
mkdir -p ~/projects/models
"

log "Installation de l'environnement de backtesting terminée!"
log "Accédez à Jupyter Lab sur http://IP-DE-LA-VM:8888"
log "Pour vérifier l'état des GPUs: nvidia-smi"
```

## Points clés pour un passthrough GPU réussi

1. **L'option `x-vga=on`** est essentielle pour la première carte GPU. Cette option indique à QEMU que le périphérique est une carte graphique qui doit être traitée spécialement.

2. **Ordre d'installation**: Installez d'abord le système d'exploitation, puis configurez le passthrough GPU, et enfin installez les pilotes NVIDIA dans la VM.

3. **Type de machine q35**: Ce modèle de machine est obligatoire pour le passthrough PCIe.

4. **Arguments CPU spécifiques**: Les arguments `-cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'` sont nécessaires pour éviter l'erreur 43 avec les cartes NVIDIA.

5. **BIOS OVMF (UEFI)**: Le BIOS OVMF est nécessaire pour un passthrough GPU correct.

## Vérification de l'installation

Pour confirmer que les GPUs sont correctement détectés et configurés, exécutez :

```bash
# Liste des cartes NVIDIA détectées
lspci | grep -i nvidia

# État des cartes NVIDIA et utilisation
nvidia-smi

# Modules du noyau NVIDIA chargés
lsmod | grep nvidia

# Version du pilote NVIDIA installé
cat /proc/driver/nvidia/version
```

Ces commandes devraient montrer toutes les cartes NVIDIA GTX 1660 Super/Ti avec leurs informations détaillées, confirmant que le passthrough et l'installation des pilotes ont réussi.

## Résolution des problèmes courants

1. **"No NVIDIA GPU detected"**: Assurez-vous que l'option `x-vga=on` est appliquée à au moins une carte GPU.

2. **Erreur de démarrage de VM**: Vérifiez que l'IOMMU est activé dans le BIOS et les options de noyau de l'hôte.

3. **Pilotes non fonctionnels**: Assurez-vous que le pilote Nouveau est correctement blacklisté.

Cette configuration permet d'utiliser les 8 cartes NVIDIA pour des tâches gourmandes en calcul comme le backtesting financier ou l'apprentissage machine, avec une performance optimale grâce au passthrough direct des GPUs.

4. **Modifiez le fichier de configuration NVIDIA dans la VM**
Une fois la VM redémarrée, vous devez vous connecter et modifier la configuration NVIDIA 
pour permettre la détection de tous les GPUs:


    # Dans la VM, créez un fichier de configuration NVIDIA
    sudo nano /etc/modprobe.d/nvidia.conf
    
    # Ajoutez les lignes suivantes
    options nvidia NVreg_EnablePCIeGen3=0
    options nvidia NVreg_UsePageAttributeTable=1
    options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"

5. **Ajoutez des options au noyau Linux**


**Dans la VM, modifiez GRUB**

    sudo nano /etc/default/grub
    
**Ajoutez cette options au GRUB**

    GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm=off pci=noaer pci=realloc"

**Mettez à jour GRUB**

    sudo update-grub
 

7. **Créez un script pour forcer la détection de tous les GPUs**


    ## Dans la VM, créez un script
    sudo nano /usr/local/bin/enable-all-gpus.sh
    
    ## Avec le contenu suivant (en fonction de vos besoin GPU)

    #!/bin/bash
    for i in {0..7}; do
      echo 1 > /sys/bus/pci/devices/0000:01:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:02:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:03:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:04:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:06:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:07:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:08:00.$i/remove
      echo 1 > /sys/bus/pci/devices/0000:09:00.$i/remove
    done
    echo 1 > /sys/bus/pci/rescan
    
    # Rendre exécutable
    sudo chmod +x /usr/local/bin/enable-all-gpus.sh
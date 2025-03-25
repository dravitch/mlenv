#!/bin/bash
set -e

# Variables
IMG_SRC="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
IMG_DEST="/var/lib/vz/images/100/hiveos.qcow2"

# Conversion de l'image
qemu-img convert -f raw -O qcow2 $IMG_SRC $IMG_DEST

# Création de la VM
qm create 99 --name "HiveOS" --memory 16384 --cores 2 --net0 virtio,bridge=vmbr0 --cpu host
qm set 99 --scsihw virtio-scsi-pci --scsi0 local-lvm:100
qm importdisk 99 $IMG_DEST local-lvm
qm set 99 --boot order=scsi0

# Configuration du GPU Passthrough
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"' >> /etc/default/grub
update-grub
echo "Redémarrez le serveur pour activer IOMMU."

# ------------------------------------------

#!/bin/bash
set -e

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
ISO_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage" # Nom du pool de stockage
GPU_DEVICE="0000:01:00.0" # Identifier votre GPU principal

# Crée le répertoire où sera stockée l'image QCOW2 convertie pour la VM
mkdir -p /var/lib/vz/images/$VMID

# Convertit l'image RAW de HiveOS au format QCOW2 et la place dans le répertoire spécifié
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2

# Convertir et attacher l'image HiveOS
echo "Conversion de l'image RAW en QCOW2..."
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2

# Créer la VM HiveOS
echo "Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Attacher le disque principal converti
echo "Importation et configuration du disque principal..."
qm importdisk $VMID /var/lib/vz/images/$VMID/hiveos.qcow2 $STORAGE_POOL
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:vm-$VMID-disk-0

# Configurer le passthrough GPU
echo "Configuration du passthrough GPU..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Configurer le démarrage depuis le disque
echo "Configuration du disque de démarrage..."
qm set $VMID --boot order=scsi0

# Finalisation
echo "La VM HiveOS est configurée avec succès !"
echo "N'oubliez pas d'activer IOMMU et de redémarrer votre système si ce n'est pas déjà fait."

### -------------------------------------------------------------------
#!/bin/bash
set -e

# Configuration initiale
VMID=198
VM_NAME="HiveOS_Legacy"
ISO_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage" # Nom du pool de stockage
GPU_DEVICE="0000:01:00.0" # Identifier votre GPU principal

# Crée le répertoire où sera stockée l'image QCOW2 convertie pour la VM
mkdir -p /var/lib/vz/images/$VMID

# Convertit l'image RAW de HiveOS au format QCOW2 et la place dans le répertoire spécifié
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2


# Convertir et attacher l'image HiveOS
echo "Conversion de l'image RAW en QCOW2..."
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2

# Créer la VM HiveOS
echo "Création de la VM HiveOS en mode Legacy..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --machine pc \
  --cpu host \
  --ostype l26 \
  --agent 1

# Attacher le disque principal converti
echo "Importation et configuration du disque principal..."
qm importdisk $VMID /var/lib/vz/images/$VMID/hiveos.qcow2 $STORAGE_POOL
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:vm-$VMID-disk-0

# Configurer le passthrough GPU
echo "Configuration du passthrough GPU..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Configurer le démarrage depuis le disque
echo "Configuration du disque de démarrage..."
qm set $VMID --boot order=scsi0

# Finalisation
echo "La VM HiveOS en mode Legacy est configurée avec succès !"
echo "N'oubliez pas d'activer IOMMU et de redémarrer votre système si ce n'est pas déjà fait."

# -----------------------------------------------------------------------------------

#!/bin/bash
set -e

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
ISO_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage"
GPU_DEVICE="0000:04:00.0"  # Identifiant PCI de la carte GPU#4

# Étape 1 : Préparer les fichiers
echo ">>> Conversion de l'image RAW en QCOW2..."
mkdir -p /var/lib/vz/images/$VMID
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2

echo ">>> Vérification du fichier QCOW2 créé..."
qemu-img info /var/lib/vz/images/$VMID/hiveos.qcow2

# Étape 2 : Créer la VM
echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Étape 3 : Importer et attacher le disque principal
echo ">>> Importation et attachement du disque principal..."
qm importdisk $VMID /var/lib/vz/images/$VMID/hiveos.qcow2 $STORAGE_POOL

# Suppression des références inutilisées
if qm config $VMID | grep -q 'unused'; then
  echo ">>> Suppression des disques inutilisés..."
  qm set $VMID --delete unused0 || true
  qm set $VMID --delete unused1 || true
fi

# Attacher le disque principal à `scsi0`
echo ">>> Configuration du disque principal sur scsi0..."
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:vm-$VMID-disk-0

# Étape 4 : Ajouter un disque EFI
echo ">>> Ajout d'un disque EFI..."
qm set $VMID --efidisk0 $STORAGE_POOL:0.1

# Étape 5 : Configurer le démarrage
echo ">>> Configuration du démarrage..."
qm set $VMID --boot order=scsi0

# Étape 6 : Configurer le passthrough GPU
echo ">>> Configuration du passthrough GPU..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Étape 7 : Vérifications finales
echo ">>> Vérification de la configuration finale..."
qm config $VMID

# Étape 8 : Démarrer la VM
echo ">>> Démarrage de la VM HiveOS..."
qm start $VMID

echo ">>> La VM HiveOS a été configurée et démarrée avec succès !"


# -----------------------------------------------

#!/bin/bash
set -e  # Arrêter le script immédiatement en cas d'erreur

# Téléchargez l'image HiveOS depuis le site officiel
cd /mnt/vmstorage/iso/template/iso/
wget -O hiveos-0.6-229-stable-jammy_241231.img.xz https://download.hiveos.farm/history/hiveos-0.6-229-stable-jammy@241231.img.xz
unxz hiveos-0.6-229-stable-jammy_241231.img.xz

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
ISO_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage"
GPU_DEVICE="0000:04:00.0"  # Identifiant PCI de la carte GPU pour le passthrough

# Étape 1 : Préparer les fichiers
echo ">>> Conversion de l'image RAW en QCOW2..."
mkdir -p /var/lib/vz/images/$VMID
qemu-img convert -f raw -O qcow2 $ISO_PATH /var/lib/vz/images/$VMID/hiveos.qcow2

echo ">>> Vérification du fichier QCOW2 créé..."
qemu-img info /var/lib/vz/images/$VMID/hiveos.qcow2

# Étape 2 : Créer la VM
echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Étape 3 : Importer et attacher le disque principal
echo ">>> Importation du disque principal..."
qm importdisk $VMID /var/lib/vz/images/$VMID/hiveos.qcow2 $STORAGE_POOL

echo ">>> Configuration du disque principal sur scsi0..."
if qm config $VMID | grep -q 'unused0'; then
  echo "Le disque principal est encore marqué comme inutilisé."
  exit 1  # Sort avec une erreur si le disque n'est pas attaché correctement
fi

qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:vm-$VMID-disk-0

# Étape 4 : Ajouter un disque EFI
echo ">>> Ajout d'un disque EFI..."
qm set $VMID --efidisk0 $STORAGE_POOL:0.1

# Étape 5 : Configurer le démarrage
echo ">>> Configuration du démarrage sur scsi0..."
qm set $VMID --boot order=scsi0

# Étape 6 : Configurer le passthrough GPU
echo ">>> Configuration du passthrough GPU..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Suppression des références inutilisées si elles existent
if qm config $VMID | grep -q 'unused'; then
  echo ">>> Suppression des disques inutilisés détectés..."
  qm set $VMID --delete unused0 || true
  qm set $VMID --delete unused1 || true
fi

# Étape 7 : Vérification finale
echo ">>> Vérification de la configuration finale..."
qm config $VMID

# Étape 8 : Démarrer la VM
echo ">>> Démarrage de la VM HiveOS..."
qm start $VMID

echo ">>> La VM HiveOS a été configurée et démarrée avec succès !"

# --------------------------------------------------------------------------------------

#!/bin/bash
set -e  # Arrête le script immédiatement en cas d'erreur

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
IMG_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
RAW_DISK_PATH="/mnt/vmstorage/images/199/vm-199-disk-0.raw"
STORAGE_POOL="vm-storage"
GPU_DEVICE="0000:04:00.0"  # Identifiant PCI du GPU pour le passthrough

# Étape 1 : Convertir l'image IMG en fichier RAW
echo ">>> Conversion de l'image IMG en fichier RAW..."
mkdir -p /mnt/vmstorage/images/199
qemu-img convert -f raw -O raw $IMG_PATH $RAW_DISK_PATH

echo ">>> Vérification du fichier RAW créé..."
qemu-img info $RAW_DISK_PATH

# Étape 2 : Créer la VM
echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Étape 3 : Attacher le disque RAW directement
echo ">>> Attachement du disque RAW..."
qm set $VMID --scsi0 $RAW_DISK_PATH --scsihw virtio-scsi-pci

# Étape 4 : Ajouter un disque EFI
echo ">>> Ajout d'un disque EFI..."
qm set $VMID --efidisk0 $STORAGE_POOL:0.1

# Étape 5 : Configurer le démarrage depuis scsi0
echo ">>> Configuration de l'ordre de démarrage..."
qm set $VMID --boot order=scsi0

# Étape 6 : Configurer le passthrough GPU
echo ">>> Configuration du passthrough GPU..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Étape 7 : Vérification finale
echo ">>> Vérification de la configuration finale..."
qm config $VMID

# Étape 8 : Démarrer la VM
echo ">>> Démarrage de la VM HiveOS..."
qm start $VMID

echo ">>> La VM HiveOS a été configurée et démarrée avec succès !"

# --------------------------------------------------------------------------------------
# Source : https://lunar.computer/news/gpu-passthrough-proxmox-60/

#!/bin/bash
set -e  # Arrêter le script immédiatement en cas d'erreur

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
IMG_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage"
DISK_NAME="vm-199-disk-0.raw"
DISK_SIZE="8G"
GPU_DEVICE="0000:01:00.0"  # Identifiant PCI du GPU pour le passthrough
AUDIO_DEVICE="0000:01:00.1"  # Identifiant PCI de l'audio associé (si nécessaire)

# Étape 1 : Préparer le disque virtuel
echo ">>> Création d'un disque virtuel pour la VM..."
pvesm alloc $STORAGE_POOL $VMID $DISK_NAME $DISK_SIZE

echo ">>> Attachement du disque virtuel à la VM..."
qm set $VMID --scsi0 $STORAGE_POOL:$DISK_NAME --scsihw virtio-scsi-pci

echo ">>> Flashage de l'image HiveOS sur le disque virtuel..."
dd if=$IMG_PATH of=/var/lib/vz/images/$VMID/$DISK_NAME bs=4M status=progress

# Étape 2 : Créer la VM HiveOS
echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

echo ">>> Ajout d'un disque EFI..."
qm set $VMID --efidisk0 $STORAGE_POOL:0.1

echo ">>> Configuration de l'ordre de démarrage..."
qm set $VMID --boot order=scsi0

# Étape 3 : Activer le GPU Passthrough
echo ">>> Configuration du GPU Passthrough..."
echo "vfio" > /etc/modules-load.d/vfio.conf
echo "vfio_iommu_type1" >> /etc/modules-load.d/vfio.conf
echo "vfio_pci" >> /etc/modules-load.d/vfio.conf
echo "vfio_virqfd" >> /etc/modules-load.d/vfio.conf

echo ">>> Ajout des options VFIO pour le GPU et l'audio..."
echo "options vfio-pci ids=$GPU_DEVICE,$AUDIO_DEVICE" > /etc/modprobe.d/vfio.conf

echo ">>> Mise à jour des images initramfs..."
update-initramfs -u -k all

echo ">>> Configuration de GRUB pour activer IOMMU..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' /etc/default/grub
update-grub

echo ">>> Ajout du GPU à la VM..."
qm set $VMID --hostpci0 $GPU_DEVICE,x-vga=on

# Étape 4 : Vérifications finales
echo ">>> Vérification de la configuration de la VM..."
qm config $VMID

echo ">>> Redémarrage du serveur pour appliquer les modifications..."
reboot

# ----------------------------------------------------------------------

# DERNIERE CONFIGURATION
#!/bin/bash
set -e  # Arrêter le script immédiatement en cas d'erreur

# Configuration initiale
VMID=198
VM_NAME="HiveOS"
IMG_PATH="/mnt/vmstorage/iso/template/iso/hiveos-0.6-229-stable-jammy_241231.img"
STORAGE_POOL="vm-storage"
DISK_NAME="vm-198-disk-0.raw"
DISK_SIZE="8G"
GPU_DEVICE="0000:06:00"  # Identifiant PCI du GPU pour le passthrough

echo ">>> Suppression des anciennes configurations pour la VM (si elles existent)..."
# Supprimer la VM si elle existe déjà
if qm status $VMID &> /dev/null; then
  qm stop $VMID || true
  qm destroy $VMID || true
fi

# Supprimer le disque virtuel s'il existe déjà
if pvesm list $STORAGE_POOL | grep -q "$VMID"; then
  echo ">>> Suppression de l'ancien disque virtuel : $DISK_NAME"
  pvesm free $STORAGE_POOL:$VMID/$DISK_NAME
fi

echo ">>> Création d'un disque virtuel pour la VM..."
pvesm alloc $STORAGE_POOL $VMID $DISK_NAME $DISK_SIZE

# Récupérer le chemin complet du disque virtuel
DISK_PATH="/mnt/vmstorage/images/images/$VMID/$DISK_NAME"
if [ ! -f "$DISK_PATH" ]; then
  echo "Erreur : Le disque virtuel $DISK_PATH n'existe pas après l'allocation."
  exit 1
fi

echo ">>> Flashage de l'image HiveOS sur le disque virtuel..."
dd if=$IMG_PATH of=$DISK_PATH bs=4M status=progress

echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 8192 --cores 1 \
  --net0 e1000,bridge=vmbr0,firewall=1,macaddr=BC:24:11:D3:79:AE \
  --bios ovmf \
  --machine q35 \
  --cpu x86-64-v2-AES \
  --ostype l26 \
  --numa 0 \
  --sockets 1 \
  --scsihw virtio-scsi-pci

echo ">>> Attachement du disque bootable à la VM..."
qm set $VMID --scsi0 $STORAGE_POOL:$VMID/$DISK_NAME,format=raw

echo ">>> Ajout d'un disque EFI pour le démarrage UEFI..."
qm set $VMID --efidisk0 $STORAGE_POOL:0.1

echo ">>> Ajout du GPU Passthrough..."
qm set $VMID --hostpci0 $GPU_DEVICE,pcie=1

echo ">>> Configuration de l'ordre de démarrage sur le disque..."
qm set $VMID --boot order=scsi0

echo ">>> Vérification de la configuration de la VM..."
qm config $VMID

# Fin
echo ">>> Configuration de la VM HiveOS terminée !"
echo ">>> Vous pouvez démarrer la VM en exécutant : qm start $VMID"

# ---------------------------------------------------------------------
#!/bin/bash
set -e  # Arrêter le script immédiatement en cas d'erreur

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
USB_DEVICE="2-2.2"  # ID de la clé USB, obtenu avec 'lsusb'
STORAGE_POOL="vm-storage"
EFI_DISK="vm-199-disk-1.raw"
EFI_SIZE="1M"  # Taille corrigée pour éviter l'erreur

# Liste des GPU (Identifiants PCI)
GPU_DEVICES=(
  "0000:01:00.0"
  "0000:02:00.0"
  "0000:03:00.0"
  "0000:04:00.0"
  "0000:06:00.0"
  "0000:07:00.0"
  "0000:08:00.0"
  "0000:09:00.0"
)

echo ">>> Suppression des anciennes configurations pour la VM (si elles existent)..."
# Supprimer la VM si elle existe déjà
if qm status $VMID &> /dev/null; then
  qm stop $VMID || true
  qm destroy $VMID || true
fi

echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 virtio=BC:24:11:D1:4F:93,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

echo ">>> Création explicite du disque EFI..."
pvesm alloc $STORAGE_POOL $VMID $EFI_DISK $EFI_SIZE

echo ">>> Attachement du disque EFI à la VM..."
qm set $VMID --efidisk0 $STORAGE_POOL:$VMID/$EFI_DISK

echo ">>> Suppression de tout disque SCSI inutilisé..."
qm set $VMID --delete scsi0 || true

echo ">>> Ajout de la clé USB comme périphérique principal..."
qm set $VMID --usb0 host=$USB_DEVICE

echo ">>> Ajout de tous les GPU à la VM..."
for GPU in "${GPU_DEVICES[@]}"; do
  echo ">>> Ajout du GPU $GPU..."
  qm set $VMID --hostpci${GPU:5:1} $GPU,pcie=1,x-vga=on
done

echo ">>> Configuration de l'ordre de démarrage..."
qm set $VMID --boot order=usb0

echo ">>> Vérification de la configuration de la VM..."
qm config $VMID

echo ">>> Démarrage de la VM HiveOS..."
qm start $VMID

echo ">>> La VM HiveOS a été configurée avec succès avec la clé USB comme périphérique de démarrage et tous les GPU ajoutés !"

## -------------------------------------------------------------------------

#!/bin/bash
set -e  # Arrêter le script immédiatement en cas d'erreur

# Configuration initiale
VMID=199
VM_NAME="HiveOS"
USB_DEVICE="2-2.2"  # ID de la clé USB, obtenu avec 'lsusb'
STORAGE_POOL="vm-storage"
EFI_DISK="vm-199-disk-1.raw"
EFI_SIZE="1M"  # Taille du disque EFI

echo ">>> Suppression des anciennes configurations pour la VM (si elles existent)..."
# Supprimer la VM si elle existe déjà
if qm status $VMID &> /dev/null; then
  qm stop $VMID || true
  qm destroy $VMID || true
fi

echo ">>> Création de la VM HiveOS..."
qm create $VMID --name $VM_NAME --memory 16384 --cores 2 \
  --net0 e1000=BC:24:11:D1:4F:93,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

echo ">>> Création explicite du disque EFI..."
pvesm alloc $STORAGE_POOL $VMID $EFI_DISK $EFI_SIZE

echo ">>> Attachement du disque EFI à la VM..."
qm set $VMID --efidisk0 $STORAGE_POOL:$VMID/$EFI_DISK

echo ">>> Désactivation du ballooning de la mémoire..."
qm set $VMID --balloon 0

echo ">>> Ajout de la clé USB comme périphérique principal..."
qm set $VMID --usb0 host=$USB_DEVICE

echo ">>> Détection des GPUs disponibles..."
GPU_DEVICES=($(lspci | grep -i vga | awk '{print $1}'))

echo ">>> Ajout de tous les GPUs détectés à la VM..."
GPU_SLOT=0  # Variable pour les slots PCI
for GPU in "${GPU_DEVICES[@]}"; do
  echo ">>> Ajout du GPU $GPU au slot hostpci${GPU_SLOT}..."
  qm set $VMID --hostpci${GPU_SLOT} 0000:$GPU,pcie=1,rombar=0
  ((GPU_SLOT++))  # Incrémente le slot PCI pour le prochain GPU
done

echo ">>> Ajout du socket série..."
qm set $VMID --serial0 socket

echo ">>> Configuration de l'ordre de démarrage sur l'USB..."
qm set $VMID --boot order=usb0

echo ">>> Vérification de la configuration de la VM..."
qm config $VMID

echo ">>> Démarrage de la VM HiveOS..."
qm start $VMID

echo ">>> La VM HiveOS a été configurée avec succès avec tous les GPUs détectés, la clé USB comme périphérique de démarrage, le ballooning désactivé, et un socket série ajouté !"

# Partie à ajouter au début du script de configuration de la VM dans Proxmox
# Création de la VM avec un disque plus grand
qm create 100 --name "BacktestingVM" --memory 8192 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --cpu host \
  --ostype l26 \
  --agent 1

# Ajouter un disque système de 60GB
qm set 100 --sata0 vm-storage:60,ssd=1

# Optionnel: Ajouter un disque séparé pour les données
qm set 100 --sata1 vm-storage:40,ssd=1
#!/bin/bash
# Script de sauvegarde pour PredatorX
# À exécuter quotidiennement via cron

DATE=
BACKUP_DIR="/mnt/vmstorage/backups"
LOG_FILE="/var/log/pve-backup/backup-\.log"

mkdir -p /var/log/pve-backup
echo "Démarrage des sauvegardes: \03/15/2025 10:32:14" | tee -a "\"

# Sauvegarde des VMs
for VM_ID in \
do
    echo "Sauvegarde de la VM \..." | tee -a "\"
    vzdump \ --compress zstd --mode snapshot --storage backup | tee -a "\"
done

# Sauvegarde des conteneurs
for CT_ID in \
do
    echo "Sauvegarde du conteneur \..." | tee -a "\"
    vzdump \ --compress zstd --mode snapshot --storage backup | tee -a "\"
done

# Conservation des 7 derniers jours de logs uniquement
find /var/log/pve-backup -name "backup-*.log" -mtime +7 -delete

echo "Sauvegardes terminées: \03/15/2025 10:32:14" | tee -a "\"

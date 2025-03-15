#!/bin/bash
# Script de maintenance pour PredatorX
# À exécuter périodiquement via cron

# Nettoyage des journaux
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.[0-9]" -delete
journalctl --vacuum-time=3d

# Nettoyage des paquets
apt clean
apt autoremove -y

# Vérification de l'espace disque
DISK_USAGE=\
if [ "\" -gt 85 ]; then
    echo "ALERTE: L'espace disque sur / est à \%" | mail -s "Alerte espace disque sur PredatorX" root
fi

# Mise à jour de l'hôte
apt update && apt list --upgradable

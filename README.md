# MLENV - Infrastructure Automatisée pour Trading Algorithmique

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

MLENV est un projet d'Infrastructure as Code (IaC) conçu pour automatiser le déploiement d'un environnement complet de backtesting et machine learning pour le trading algorithmique sur un système multi-GPU.

## Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Prérequis](#prérequis)
- [Architecture](#architecture)
- [Installation rapide](#installation-rapide)
- [Configuration](#configuration)
- [Utilisation](#utilisation)
- [Maintenance](#maintenance)
- [Contribuer](#contribuer)
- [Licence](#licence)

## Vue d'ensemble

Ce projet transforme un serveur multi-GPU en une plateforme puissante pour:
- Développer et tester des stratégies de trading algorithmique (backtesting)
- Appliquer des techniques de machine learning aux données financières
- Optimiser les performances des modèles grâce au calcul GPU accéléré
- Centraliser le stockage et l'analyse des données financières

## Prérequis

### Matériel
- Serveur avec processeur x86_64 (Intel/AMD)
- 16GB+ RAM
- Cartes graphiques NVIDIA compatibles avec CUDA
- SSD pour le système d'exploitation
- Stockage secondaire pour les données (optionnel mais recommandé)

### Logiciels
- ISO Proxmox VE 8.x
- Clé USB pour l'installation
- Connexion internet pour télécharger les paquets
- Git pour le clonage du dépôt
- PowerShell (Windows) ou Bash (Linux/macOS)

## Architecture

```
┌─────────────────────────────────────┐
│ Proxmox VE (Système hôte)           │
│                                     │
│ ┌─────────────┐    ┌─────────────┐  │
│ │ VM          │    │ VM          │  │
│ │ Backtesting │    │ Machine     │  │
│ │ Python      │    │ Learning    │  │
│ │ Jupyter     │    │ TensorFlow  │  │
│ └─────────────┘    └─────────────┘  │
│                                     │
│ ┌─────────────┐    ┌─────────────┐  │
│ │ Conteneur   │    │ Conteneur   │  │
│ │ PostgreSQL  │    │ Sauvegardes │  │
│ └─────────────┘    └─────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

## Installation rapide

### Sur Windows (développement)

```powershell
# Cloner le dépôt
git clone https://github.com/votre-username/mlenv.git
cd mlenv

# Générer la structure du projet
.\Create-ProjectStructure.ps1
```

### Sur Linux (déploiement)

```bash
# Installer Proxmox VE 8 (manuellement depuis l'ISO)

# Après installation de Proxmox:
apt update && apt install -y git

# Cloner le dépôt
git clone https://github.com/votre-username/mlenv.git
cd mlenv

# Configuration de Proxmox
bash proxmox/post-install.sh

# Configuration du GPU Passthrough
bash proxmox/progressive-gpu-passthrough.sh

# Redémarrer le système
reboot

# Configuration des VM et conteneurs via Ansible
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## Configuration

### Personnalisation de l'environnement

1. Copiez le fichier d'exemple de configuration:
   ```bash
   cp .env.example .env
   ```

2. Modifiez les variables dans `.env` selon votre environnement:
   - `MLENV_HOST_IP`: Adresse IP de l'hôte Proxmox
   - `MLENV_STORAGE_PATH`: Chemin du stockage principal
   - `MLENV_GPU_IDS`: IDs des GPUs à utiliser (format: "10de:xxxx,10de:yyyy")

3. Appliquez la configuration:
   ```bash
   # Sur Windows
   .\scripts\Apply-Configuration.ps1
   
   # Sur Linux
   bash scripts/apply-configuration.sh
   ```

### Configuration des GPU

Pour personnaliser l'attribution des GPU aux VMs:

1. Listez vos GPU disponibles:
   ```bash
   lspci -nn | grep -i nvidia
   ```

2. Modifiez le fichier `ansible/inventory/group_vars/all.yml`:
   ```yaml
   gpu_config:
     backtesting_vm:
       - "01:00.0"  # Premier GPU pour la VM de backtesting
     ml_vm:
       - "02:00.0"  # Deuxième GPU pour la VM de ML
       - "03:00.0"  # Troisième GPU pour la VM de ML
   ```

## Utilisation

### Accès aux environnements

- **Interface Proxmox**: https://IP-HOTE:8006
- **Jupyter Backtesting**: http://IP-VM-BACKTESTING:8888
- **Jupyter Machine Learning**: http://IP-VM-ML:8888
- **PostgreSQL**: postgresql://IP-CONTENEUR-DB:5432

### Vérification du passthrough GPU

```bash
# Se connecter à la VM via SSH
ssh user@IP-VM

# Vérifier que les GPU sont détectés
nvidia-smi
```

### Exécution de stratégies de backtesting

1. Téléchargez des données financières:
   ```python
   import yfinance as yf
   data = yf.download("SPY", period="5y")
   data.to_csv("spy_data.csv")
   ```

2. Exécutez une stratégie de test:
   ```bash
   cd projects/strategies
   python test_strategy.py
   ```

## Maintenance

### Sauvegardes

```bash
# Sauvegarde manuelle
bash /usr/local/bin/pve-backup.sh

# Vérification des sauvegardes existantes
ls -la /mnt/vmstorage/backups
```

### Mises à jour

```bash
# Mise à jour de Proxmox
apt update && apt upgrade -y

# Mise à jour du projet MLENV
cd /path/to/mlenv
git pull
```

### Nettoyage

```bash
# Nettoyage du système
bash scripts/maintenance.sh
```

## Contribuer

Les contributions sont les bienvenues! Veuillez suivre ces étapes:

1. Forkez le dépôt
2. Créez une branche pour votre fonctionnalité (`git checkout -b feature/ma-fonctionnalite`)
3. Committez vos changements (`git commit -am 'Ajout de ma fonctionnalité'`)
4. Poussez vers la branche (`git push origin feature/ma-fonctionnalite`)
5. Créez une Pull Request

## Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.
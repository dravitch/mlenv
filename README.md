# MLENV - Infrastructure Automatisée pour Trading Algorithmique

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

MLENV est un projet d'Infrastructure as Code (IaC) conçu pour automatiser le déploiement d'un environnement complet de backtesting et machine learning pour le trading algorithmique sur un système multi-GPU.

## Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Structure du projet](#structure-du-projet)
- [Prérequis](#prérequis)
- [Installation rapide](#installation-rapide)
- [Configuration](#configuration)
- [Utilisation](#utilisation)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)
- [Contribuer](#contribuer)
- [Licence](#licence)

## Vue d'ensemble

Ce projet transforme un serveur multi-GPU en une plateforme puissante pour:
- Développer et tester des stratégies de trading algorithmique (backtesting)
- Appliquer des techniques de machine learning aux données financières
- Optimiser les performances des modèles grâce au calcul GPU accéléré
- Centraliser le stockage et l'analyse des données financières

## Structure du projet

```
mlenv/
├── ansible/                       # Configuration Ansible
│   ├── ansible.cfg               # Configuration Ansible
│   ├── inventory/                # Inventaire
│   │   ├── hosts.yml             # Définition des hôtes
│   │   └── group_vars/           # Variables par groupe
│   │       └── all.yml           # Variables globales
│   ├── playbooks/                # Playbooks
│   │   ├── site.yml              # Playbook principal
│   │   ├── proxmox-setup.yml     # Configuration Proxmox
│   │   ├── backtesting-vm.yml    # VM de backtesting
│   │   ├── ml-vm.yml             # VM de machine learning
│   │   ├── container-setup.yml   # Conteneurs LXC
│   │   ├── backtesting-vm-setup.yml # Config. environnement backtesting
│   │   └── ml-vm-setup.yml       # Config. environnement ML
│   ├── templates/                # Templates Jinja2
│   └── roles/                    # Rôles Ansible
├── proxmox/                      # Scripts Proxmox
│   ├── post-install.sh           # Configuration post-installation
│   └── progressive-gpu-passthrough.sh # Config. GPU passthrough
├── storage/                      # Scripts de stockage
│   └── setup-m2-storage.sh       # Configuration stockage M.2
├── scripts/                      # Scripts utilitaires
│   ├── apply-configuration.sh    # Application des variables (Linux)
│   ├── Apply-Configuration.ps1   # Application des variables (Windows)
│   └── update-inventory.sh       # Mise à jour de l'inventaire Ansible
├── config/                       # Fichiers de configuration
├── doc/                          # Documentation
├── .env.example                  # Exemple de variables d'environnement
└── README.md                     # Documentation générale
```

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

## Installation rapide

### Configuration initiale

1. **Cloner le dépôt**
   ```bash
   git clone https://github.com/votre-username/mlenv.git
   cd mlenv
   ```

2. **Personnaliser la configuration**
   ```bash
   # Sur Linux/macOS
   cp .env.example .env
   nano .env
   
   # Sur Windows
   copy .env.example .env
   notepad .env
   ```

3. **Appliquer la configuration**
   ```bash
   # Sur Linux/macOS
   bash scripts/apply-configuration.sh
   
   # Sur Windows
   powershell -ExecutionPolicy Bypass -File .\scripts\Apply-Configuration.ps1
   ```

### Installation de Proxmox

1. **Installer Proxmox VE 8.x**
   - Télécharger l'ISO depuis [proxmox.com](https://www.proxmox.com/en/downloads)
   - Créer une clé USB bootable
   - Installer Proxmox en suivant l'assistant

2. **Configuration post-installation**
   ```bash
   # Se connecter au serveur Proxmox en SSH
   ssh root@IP-DU-SERVEUR
   
   # Cloner le dépôt
   apt update && apt install -y git
   git clone https://github.com/votre-username/mlenv.git /root/mlenv
   cd /root/mlenv
   
   # Exécuter le script de post-installation
   bash proxmox/post-install.sh
   ```

3. **Configuration du stockage M.2 (si disponible)**
   ```bash
   bash storage/setup-m2-storage.sh
   ```

4. **Configuration du passthrough GPU**
   ```bash
   bash proxmox/progressive-gpu-passthrough.sh
   ```

5. **Redémarrer le serveur**
   ```bash
   reboot
   ```

### Déploiement de l'infrastructure

```bash
# Connexion au serveur et mise à jour de l'inventaire Ansible
cd /root/mlenv
bash scripts/update-inventory.sh

# Installation d'Ansible
apt install -y ansible

# Déploiement de l'infrastructure
cd ansible
ansible-playbook playbooks/site.yml
```

## Configuration

MLENV utilise un système de variables d'environnement pour personnaliser le déploiement. Toutes les variables sont centralisées dans le fichier `.env` et sont appliquées automatiquement aux fichiers de configuration Ansible.

### Variables principales

| Variable | Description | Valeur par défaut |
|----------|-------------|-------------------|
| `MLENV_HOST_IP` | Adresse IP du serveur Proxmox | `192.168.1.100` |
| `MLENV_STORAGE_PATH` | Chemin du stockage principal | `/mnt/vmstorage` |
| `MLENV_GPU_IDS` | IDs des GPUs NVIDIA | `10de:2184,10de:1e84` |
| `MLENV_BACKTESTING_GPU_INDICES` | Indices des GPUs pour le backtesting | `0` |
| `MLENV_ML_GPU_INDICES` | Indices des GPUs pour le ML | `1,2,3,4,5,6,7` |
| `MLENV_VM_MEMORY` | Mémoire allouée aux VMs (Mo) | `4096` |
| `MLENV_VM_CORES` | Nombre de cœurs CPU alloués aux VMs | `2` |

Voir le fichier `.env.example` pour la liste complète des variables.

### Gestion des variables

1. **Environnement local**:
   - Variables dans `.env`
   - Application via `scripts/apply-configuration.sh` ou `scripts/Apply-Configuration.ps1`

2. **Environnement Ansible**:
   - Inventaire dans `ansible/inventory/hosts.yml`
   - Variables globales dans `ansible/inventory/group_vars/all.yml`
   - Mise à jour via `scripts/update-inventory.sh`

## Utilisation

### Accès aux environnements

Après le déploiement, vous pouvez accéder aux différents environnements:

- **Interface Proxmox**: https://IP-HOTE:8006
- **Jupyter Backtesting**: http://IP-VM-BACKTESTING:8888
- **Jupyter Machine Learning**: http://IP-VM-ML:8888
- **PostgreSQL**: postgresql://IP-CONTENEUR-DB:5432

### Commandes Ansible utiles

```bash
# Déploiement complet
ansible-playbook playbooks/site.yml

# Uniquement VMs
ansible-playbook playbooks/site.yml --tags vms

# Uniquement backtesting
ansible-playbook playbooks/site.yml --tags backtesting

# Seulement conteneurs
ansible-playbook playbooks/site.yml --tags containers
```

## Maintenance

### Sauvegardes

Des sauvegardes quotidiennes sont configurées automatiquement. Pour lancer une sauvegarde manuelle:

```bash
# Sur l'hôte Proxmox
/usr/local/bin/pve-backup.sh
```

### Mises à jour

```bash
# Mise à jour du dépôt
cd /root/mlenv
git pull

# Mise à jour de l'inventaire
bash scripts/update-inventory.sh

# Redéploiement
cd ansible
ansible-playbook playbooks/site.yml
```

## Dépannage

Consultez le document [doc/proxmox-recovery-plan.md](doc/proxmox-recovery-plan.md) pour des instructions détaillées sur la récupération du système en cas de problème.

### Problèmes courants

1. **Problèmes de passthrough GPU**
   - Vérifiez que l'IOMMU est activé dans le BIOS
   - Utilisez `lspci -nnk | grep -i nvidia -A3` pour vérifier l'état des GPUs
   - En cas de problème, utilisez `/boot/restore-boot.sh` pour restaurer la configuration

2. **VMs ne démarrant pas**
   - Vérifiez les logs: `tail -f /var/log/pve/qemu-server/VM_ID.log`
   - Essayez sans passthrough GPU puis ajoutez-les progressivement

3. **Problèmes d'installation OS dans les VMs**
   - Vérifiez que l'ISO est bien disponible: `pvesm list iso`
   - Utilisez l'interface web Proxmox pour suivre l'installation

## Contribuer

Les contributions sont les bienvenues! Veuillez suivre ces étapes:

1. Forkez le dépôt
2. Créez une branche pour votre fonctionnalité (`git checkout -b feature/ma-fonctionnalite`)
3. Committez vos changements (`git commit -am 'Ajout de ma fonctionnalité'`)
4. Poussez vers la branche (`git push origin feature/ma-fonctionnalite`)
5. Créez une Pull Request

## Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.
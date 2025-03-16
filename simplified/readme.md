# Documentation du Projet PredatorX
# Serveur de Backtesting et Machine Learning pour le Trading Algorithmique
# Version simplifiée

## Table des matières
1. [Vue d'ensemble du projet](#1-vue-densemble-du-projet)
   - [Objectifs](#objectifs)
   - [Architecture globale](#architecture-globale)
   - [Matériel utilisé](#matériel-utilisé)
2. [Installation de Proxmox VE](#2-installation-de-proxmox-ve)
   - [Prérequis](#prérequis)
   - [Installation du système](#installation-du-système)
   - [Configuration post-installation](#configuration-post-installation)
3. [Configuration GPU Passthrough](#3-configuration-gpu-passthrough)
   - [Configuration progressive](#configuration-progressive)
   - [Vérification du fonctionnement](#vérification-du-fonctionnement)
   - [Résolution des problèmes courants](#résolution-des-problèmes-courants)
4. [Configuration des machines virtuelles](#4-configuration-des-machines-virtuelles)
   - [VM de Backtesting](#vm-de-backtesting)
   - [VM de Machine Learning](#vm-de-machine-learning)
5. [Configuration des environnements de trading](#5-configuration-des-environnements-de-trading)
   - [Environnement de backtesting](#environnement-de-backtesting)
   - [Environnement de machine learning](#environnement-de-machine-learning)
6. [Sauvegarde et maintenance](#6-sauvegarde-et-maintenance)
   - [Stratégie de sauvegarde](#stratégie-de-sauvegarde)
   - [Maintenance régulière](#maintenance-régulière)
7. [Annexes](#7-annexes)
   - [Liste des scripts](#liste-des-scripts)
   - [Références](#références)

## 1. Vue d'ensemble du projet

### Objectifs
Le projet PredatorX vise à repurposer une ancienne machine de minage de cryptomonnaies en un serveur de calcul dédié pour:
- Développer et tester des stratégies de trading algorithmique (backtesting)
- Appliquer des techniques de machine learning aux données financières
- Optimiser les stratégies de trading pour améliorer le ratio rendement/drawdown
- Centraliser stockage et analyse des données financières

### Architecture globale
L'architecture mise en place s'articule autour d'un système de virtualisation (Proxmox VE) qui permet de compartimenter les différentes charges de travail:

1. **Système hôte (Proxmox VE)**
   - Installé sur le disque SSD principal
   - Gère la virtualisation et le passthrough GPU

2. **Machines virtuelles**
   - VM de backtesting principal (avec 1-2 GPUs)
   - VM de machine learning (avec les GPUs restants)

3. **Stockage**
   - Disque SSD pour l'OS
   - Stockage secondaire monté pour les VMs et les données

### Matériel utilisé
- **Processeur**: Intel Celeron G4930 (2 cœurs)
- **Mémoire**: 32 GB RAM DDR4
- **Stockage**:
  - SSD Kingston A400 120GB (système)
  - Disque M.2 SATA3 de 512 GB (stockage principal)
  - Disque externe USB de 1 TB (sauvegardes, optionnel)
- **GPUs**: 8x NVIDIA GTX 1660 Super/Ti
- **Réseau**: Interface réseau Gigabit

## 2. Installation de Proxmox VE

### Prérequis
- ISO Proxmox VE 8.x
- Support d'installation USB
- Accès physique à la machine pour l'installation initiale
- Connexion réseau configurée

### Installation du système
1. Créer une clé USB bootable avec l'ISO Proxmox VE
2. Démarrer la machine depuis la clé USB
3. Suivre l'assistant d'installation avec les paramètres suivants:
   - Langue et clavier selon préférences
   - Disque d'installation: SSD Kingston A400
   - Allouer au moins 50 GB pour la partition racine
   - Configurer le nom d'hôte: predatorx
   - Configurer les paramètres réseau
   - Définir un mot de passe root sécurisé

Alternativement, vous pouvez utiliser le script `proxmox-installation.sh` pour automatiser l'installation sur une base Debian:

```bash
# Télécharger et exécuter le script d'installation
wget -O /tmp/proxmox-installation.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/proxmox-installation.sh
chmod +x /tmp/proxmox-installation.sh
sudo /tmp/proxmox-installation.sh
```

### Configuration post-installation
Après l'installation, exécuter le script de post-installation pour configurer l'environnement:

```bash
# Télécharger et exécuter le script de post-installation
wget -O /tmp/post-installation.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/post-installation.sh
chmod +x /tmp/post-installation.sh
sudo /tmp/post-installation.sh
```

Ce script effectue les actions suivantes:
- Configuration des dépôts Proxmox (désactivation des dépôts enterprise)
- Configuration du stockage
- Installation des templates LXC
- Configuration du pare-feu
- Configuration des sauvegardes automatiques
- Désactivation de la fenêtre contextuelle d'abonnement

### Configuration du stockage M.2
Si vous disposez d'un disque M.2 pour le stockage principal (comme dans notre configuration), configurez-le:

```bash
# Télécharger et exécuter le script de configuration du stockage M.2
wget -O /tmp/setup-m2-storage.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/storage/setup-m2-storage.sh
chmod +x /tmp/setup-m2-storage.sh
sudo /tmp/setup-m2-storage.sh
```

Ce script effectue:
1. Détection du disque M.2 SATA
2. Création de partitions et formatage
3. Montage du disque sur `/mnt/vmstorage`
4. Configuration des stockages dans Proxmox (vm-storage, ct-storage, backup, iso)
5. Configuration du montage automatique au démarrage

## 3. Configuration GPU Passthrough

### Configuration progressive
Pour configurer le passthrough GPU de manière sécurisée et progressive:

```bash
# Télécharger et exécuter le script de configuration progressive
wget -O /tmp/progressive-gpu-passthrough.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/progressive-gpu-passthrough.sh
chmod +x /tmp/progressive-gpu-passthrough.sh
sudo /tmp/progressive-gpu-passthrough.sh
```

Ce script effectue:
1. Vérification des prérequis matériels (support IOMMU)
2. Configuration de GRUB pour activer l'IOMMU
3. Configuration des modules VFIO
4. Détection des cartes GPU NVIDIA
5. Configuration progressive du passthrough, en commençant par une seule carte
6. Instructions détaillées pour tester et ajouter plus de cartes

### Vérification du fonctionnement
Après redémarrage, vérifiez que le passthrough GPU fonctionne:

```bash
# Vérifier les modules VFIO chargés
lsmod | grep vfio

# Vérifier que les cartes sont attribuées à VFIO
lspci -nnk | grep -i nvidia -A3
```

### Résolution des problèmes courants
En cas de problème avec le passthrough GPU:

1. **Système qui ne démarre pas**:
   - Démarrer en mode recovery
   - Exécuter `/recovery/restore-boot.sh` pour désactiver temporairement le passthrough

2. **GPUs non détectés dans la VM**:
   - Vérifier que l'option `x-vga=on` est utilisée pour au moins une carte
   - Vérifier les options de machine de la VM (q35, OVMF, etc.)

3. **Erreur 43 NVIDIA**:
   - Utiliser les options CPU spéciales: `args: -cpu 'host,+kvm_pv_unhalt,+kvm_pv_eoi,hv_vendor_id=NV43FIX,kvm=off'`

## 4. Configuration des machines virtuelles

### VM de Backtesting
Pour créer et configurer la VM de backtesting:

```bash
# Télécharger et exécuter le script de création de VM de backtesting
wget -O /tmp/setup-backtesting-vm.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/setup-backtesting-vm.sh
chmod +x /tmp/setup-backtesting-vm.sh
sudo /tmp/setup-backtesting-vm.sh
```

Ce script effectue:
1. Création d'une VM avec les paramètres adaptés (8GB RAM, 40GB disque, etc.)
2. Configuration du passthrough d'un ou deux GPUs
3. Configuration du BIOS OVMF et des options de machine q35
4. Ajout de l'ISO d'installation Ubuntu 22.04

Après la création, installez manuellement Ubuntu 22.04 Server via la console Proxmox.

### VM de Machine Learning
Pour créer et configurer la VM de machine learning:

```bash
# Télécharger et exécuter le script de création de VM de machine learning
wget -O /tmp/setup-ml-vm.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/setup-ml-vm.sh
chmod +x /tmp/setup-ml-vm.sh
sudo /tmp/setup-ml-vm.sh
```

Ce script effectue une configuration similaire à la VM de backtesting, mais avec l'attribution de plusieurs GPUs.

## 5. Configuration des environnements de trading

### Environnement de backtesting
Après avoir installé Ubuntu dans la VM de backtesting, exécutez:

```bash
# Dans la VM de backtesting, télécharger et exécuter le script de configuration
wget -O /tmp/setup-backtesting.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/setup-backtesting.sh
chmod +x /tmp/setup-backtesting.sh
sudo /tmp/setup-backtesting.sh
```

Ce script installe:
- Pilotes NVIDIA et CUDA
- Python et bibliothèques pour le backtesting (pandas, numpy, backtrader, etc.)
- Jupyter Lab
- Service systemd pour Jupyter
- Structure de projet pour le backtesting

### Environnement de machine learning
Dans la VM de machine learning:

```bash
# Télécharger et exécuter le script de configuration ML
wget -O /tmp/setup-ml.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/setup-ml.sh
chmod +x /tmp/setup-ml.sh
sudo /tmp/setup-ml.sh
```

Ce script installe des composants similaires à la VM de backtesting, plus:
- Bibliothèques spécifiques pour le machine learning (TensorFlow, PyTorch, etc.)
- Outils d'optimisation et d'apprentissage par renforcement
- Structure de projet pour le ML

## 6. Sauvegarde et maintenance

### Stratégie de sauvegarde
Le script post-installation configure des sauvegardes automatiques avec:

- Sauvegarde quotidienne des VMs à 1h du matin
- Compression zstd pour économiser de l'espace
- Logs de sauvegarde dans /var/log/pve-backup/

Vous pouvez déclencher une sauvegarde manuelle:

```bash
# Exécuter le script de sauvegarde
/usr/local/bin/pve-backup.sh
```

### Maintenance régulière
Pour la maintenance du système:

```bash
# Télécharger et exécuter le script de maintenance
wget -O /tmp/maintenance.sh https://raw.githubusercontent.com/dravitch/mlenv/simplified/maintenance.sh
chmod +x /tmp/maintenance.sh
sudo /tmp/maintenance.sh
```

Ce script effectue:
- Nettoyage des journaux
- Nettoyage des paquets
- Vérification de l'espace disque
- Mise à jour du système

## 7. Annexes

### Liste des scripts
Voici la liste complète des scripts utilisés dans ce projet:

| Script | Description |
|--------|-------------|
| `proxmox-installation.sh` | Installation de Proxmox VE sur Debian |
| `post-installation.sh` | Configuration post-installation |
| `storage/setup-m2-storage.sh` | Configuration du stockage M.2 |
| `progressive-gpu-passthrough.sh` | Configuration du passthrough GPU |
| `setup-backtesting-vm.sh` | Création de la VM de backtesting |
| `setup-ml-vm.sh` | Création de la VM de machine learning |
| `setup-backtesting.sh` | Configuration de l'environnement de backtesting |
| `setup-ml.sh` | Configuration de l'environnement de machine learning |
| `maintenance.sh` | Maintenance régulière du système |

**Note**: Tous ces scripts sont disponibles dans la branche `simplified` du dépôt GitHub: https://github.com/dravitch/mlenv/tree/simplified

### Références
- [Documentation officielle Proxmox](https://pve.proxmox.com/wiki/Main_Page)
- [Guide NVIDIA GPU Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [Guide d'installation CUDA](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/)
- [Documentation Jupyter](https://jupyter.org/documentation)
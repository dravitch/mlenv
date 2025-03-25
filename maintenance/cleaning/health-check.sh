#!/bin/bash
# health-check.sh - Script de vérification post-installation pour VM de backtesting/ML
# Analyse la configuration matérielle, les pilotes, les services et l'état général
# Usage: sudo bash health-check.sh [--detailed]

set -e

###########################################
# CONFIGURATION ET VARIABLES GLOBALES
###########################################

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DETAILED=false
if [[ "$1" == "--detailed" ]]; then
    DETAILED=true
fi

HOSTNAME=$(hostname)
KERNEL=$(uname -r)
DATE=$(date)
REPORT_FILE="vm_health_report_$(date +%Y%m%d_%H%M%S).txt"
ISSUES_FOUND=0
WARNINGS_FOUND=0

###########################################
# FONCTIONS UTILITAIRES
###########################################

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> $REPORT_FILE
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
    echo "[OK] $1" >> $REPORT_FILE
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> $REPORT_FILE
    ((WARNINGS_FOUND++))
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> $REPORT_FILE
    ((ISSUES_FOUND++))
}

section_header() {
    echo -e "\n${BLUE}======== $1 ========${NC}"
    echo -e "\n======== $1 ========" >> $REPORT_FILE
}

separator() {
    echo -e "${BLUE}----------------------------------------${NC}"
    echo "----------------------------------------" >> $REPORT_FILE
}

command_exists() {
    command -v "$1" &> /dev/null
}

# Vérification des privilèges root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

###########################################
# FONCTIONS DE VÉRIFICATION
###########################################

check_system_info() {
    section_header "INFORMATIONS SYSTÈME"

    log "Hostname: $HOSTNAME"
    log "Date et heure: $DATE"
    log "Noyau Linux: $KERNEL"
    log "Architecture: $(uname -m)"
    log "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"')"
    log "Utilisateurs connectés: $(who | wc -l)"

    # Uptime
    uptime_seconds=$(cat /proc/uptime | awk '{print $1}')
    uptime_days=$(echo "$uptime_seconds/86400" | bc)
    uptime_hours=$(echo "($uptime_seconds%86400)/3600" | bc)
    uptime_minutes=$(echo "($uptime_seconds%3600)/60" | bc)
    log "Uptime: ${uptime_days} jours, ${uptime_hours} heures, ${uptime_minutes} minutes"

    # Charge système
    load=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    log "Charge système (1, 5, 15 min): $load"
}

check_cpu_info() {
    section_header "INFORMATIONS CPU"

    log "Modèle CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')"
    log "Nombre de cœurs physiques: $(grep "cpu cores" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')"
    log "Nombre de cœurs logiques: $(grep -c "processor" /proc/cpuinfo)"

    # Vérifier les fonctionnalités de virtualisation
    if grep -q "vmx\|svm" /proc/cpuinfo; then
        success "Virtualisation CPU activée (VMX/SVM détecté)"
    else
        warning "Virtualisation CPU non détectée dans /proc/cpuinfo"
    fi

    # Vérifier si le CPU est limité/throttlé
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
        governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        log "Gouverneur de fréquence CPU: $governor"

        if [ "$governor" != "performance" ]; then
            warning "Le gouverneur de fréquence n'est pas réglé sur 'performance', ce qui peut limiter les performances"
        else
            success "Gouverneur de fréquence CPU optimisé pour la performance"
        fi
    fi
}

check_memory_info() {
    section_header "INFORMATIONS MÉMOIRE"

    total_mem=$(free -m | grep "Mem:" | awk '{print $2}')
    used_mem=$(free -m | grep "Mem:" | awk '{print $3}')
    free_mem=$(free -m | grep "Mem:" | awk '{print $4}')

    log "Mémoire totale: ${total_mem} MB ($(echo "scale=2; ${total_mem}/1024" | bc) GB)"
    log "Mémoire utilisée: ${used_mem} MB ($(echo "scale=2; ${used_mem}/${total_mem}*100" | bc)%)"
    log "Mémoire libre: ${free_mem} MB"

    # Vérifier si la mémoire est suffisante pour les charges ML
    if [ $total_mem -lt 8192 ]; then
        warning "La mémoire totale est inférieure à 8 GB, ce qui peut être insuffisant pour les charges ML"
    elif [ $total_mem -lt 16384 ]; then
        warning "La mémoire est inférieure à 16 GB, ce qui peut limiter les performances pour les gros modèles ML"
    else
        success "Mémoire suffisante pour les charges ML"
    fi

    # Vérifier le SWAP
    total_swap=$(free -m | grep "Swap:" | awk '{print $2}')
    used_swap=$(free -m | grep "Swap:" | awk '{print $3}')

    if [ $total_swap -eq 0 ]; then
        warning "Aucun espace SWAP détecté"
    else
        log "Swap total: ${total_swap} MB"
        log "Swap utilisé: ${used_swap} MB"

        # Vérifier le ratio swap/ram recommandé
        recommended_swap=$(echo "scale=0; ${total_mem}/2" | bc)
        if [ $total_swap -lt $recommended_swap ]; then
            warning "L'espace SWAP est inférieur à la valeur recommandée (${recommended_swap} MB)"
        fi
    fi
}

check_disks() {
    section_header "ESPACE DISQUE ET STOCKAGE"

    # Liste des systèmes de fichiers
    df -h -T | grep -v "tmpfs\|udev" > /tmp/disk_info.tmp

    # Afficher l'espace disque utilisé
    log "Systèmes de fichiers montés:"
    cat /tmp/disk_info.tmp | while read line; do
        echo "  $line" >> $REPORT_FILE
    done

    # Vérifier l'espace disque
    root_fs_avail=$(df -h / | awk 'NR==2 {print $4}')
    root_fs_use=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    root_fs_total=$(df -h / | awk 'NR==2 {print $2}')

    log "Espace disque racine: ${root_fs_total} total, ${root_fs_avail} disponible (${root_fs_use}% utilisé)"

    if [ "${root_fs_use}" -gt 90 ]; then
        error "Espace disque critique sur / (${root_fs_use}% utilisé)"
    elif [ "${root_fs_use}" -gt 80 ]; then
        warning "Espace disque faible sur / (${root_fs_use}% utilisé)"
    else
        success "Espace disque suffisant sur /"
    fi

    # Analyse des plus gros répertoires
    log "Les 10 plus grands répertoires dans /:"
    du -h --max-depth=2 / 2>/dev/null | sort -hr | head -10 > /tmp/large_dirs.tmp
    cat /tmp/large_dirs.tmp | while read line; do
        echo "  $line" >> $REPORT_FILE
    done

    # Si CUDA est installé, vérifier sa taille
    if [ -d "/usr/local/cuda" ]; then
        cuda_size=$(du -sh /usr/local/cuda 2>/dev/null | awk '{print $1}')
        log "Taille installation CUDA: ${cuda_size}"

        # Vérifier les répertoires CUDA qui pourraient être nettoyés
        if [ -d "/usr/local/cuda/doc" ]; then
            doc_size=$(du -sh /usr/local/cuda/doc 2>/dev/null | awk '{print $1}')
            warning "La documentation CUDA occupe ${doc_size} et pourrait être supprimée"
        fi

        if [ -d "/usr/local/cuda/samples" ]; then
            samples_size=$(du -sh /usr/local/cuda/samples 2>/dev/null | awk '{print $1}')
            warning "Les exemples CUDA occupent ${samples_size} et pourraient être supprimés"
        fi
    fi

    # Vérifier l'espace disque pour les projets
    if [ -d "/home/backtester/projects" ]; then
        projects_size=$(du -sh /home/backtester/projects 2>/dev/null | awk '{print $1}')
        log "Taille des projets de backtesting: ${projects_size}"
    fi

    # Vérifier les inodes
    inodes_used=$(df -i / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "${inodes_used}" -gt 90 ]; then
        error "Utilisation critique des inodes sur / (${inodes_used}% utilisé)"
    elif [ "${inodes_used}" -gt 80 ]; then
        warning "Utilisation élevée des inodes sur / (${inodes_used}% utilisé)"
    else
        success "Utilisation des inodes normale sur / (${inodes_used}% utilisé)"
    fi
}

check_grub_config() {
    section_header "CONFIGURATION GRUB"

    if [ -f "/etc/default/grub" ]; then
        # Capturer les paramètres de ligne de commande
        GRUB_CMDLINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | cut -d'"' -f2)
        log "Paramètres GRUB: $GRUB_CMDLINE"

        # Vérifier les paramètres importants pour la performance GPU
        if echo "$GRUB_CMDLINE" | grep -q "pcie_aspm=off"; then
            success "Paramètre pcie_aspm=off trouvé (meilleure performance PCIe)"
        else
            warning "Paramètre pcie_aspm=off non trouvé (recommandé pour les GPUs)"
        fi

        if echo "$GRUB_CMDLINE" | grep -q "pci=noaer"; then
            success "Paramètre pci=noaer trouvé (réduit les erreurs PCIe)"
        else
            warning "Paramètre pci=noaer non trouvé (recommandé pour les GPUs)"
        fi

        if echo "$GRUB_CMDLINE" | grep -q "pci=realloc"; then
            success "Paramètre pci=realloc trouvé (aide à la réallocation PCI)"
        else
            warning "Paramètre pci=realloc non trouvé (recommandé pour les multi-GPUs)"
        fi

        # Vérifier si la mise à jour de grub a été appliquée
        if which grub-mkconfig &> /dev/null && grep -q "update-grub" /var/log/apt/history.log 2>/dev/null; then
            success "GRUB a été mis à jour récemment"
        else
            warning "Aucune trace de mise à jour récente de GRUB, exécutez 'sudo update-grub' après modifications"
        fi
    else
        error "Fichier de configuration GRUB non trouvé"
    fi
}

check_gpu_passthrough() {
    section_header "PASSTHROUGH GPU"

    # Vérifier les GPUs détectés par le système
    if command_exists lspci; then
        GPU_COUNT=$(lspci | grep -i -c "NVIDIA")
        log "Nombre de périphériques NVIDIA détectés par PCI: $GPU_COUNT"

        # Liste des GPUs
        log "Liste des périphériques NVIDIA détectés:"
        lspci | grep -i "NVIDIA" > /tmp/nvidia_pci.tmp
        cat /tmp/nvidia_pci.tmp | while read line; do
            echo "  $line" >> $REPORT_FILE
        done

        if [ "$GPU_COUNT" -eq 0 ]; then
            error "Aucun GPU NVIDIA détecté via lspci"
        elif [ "$GPU_COUNT" -eq 1 ]; then
            warning "Un seul périphérique NVIDIA détecté, vérifiez le passthrough multiple"
        elif [ "$GPU_COUNT" -ge 8 ]; then
            success "Tous les périphériques NVIDIA détectés ($GPU_COUNT périphériques)"
        else
            warning "Seulement $GPU_COUNT périphériques NVIDIA détectés sur 8 attendus"
        fi
    else
        error "Commande lspci non trouvée"
    fi

    # Vérifier la configuration des modules noyau pour NVIDIA
    if [ -f "/etc/modprobe.d/nvidia.conf" ]; then
        log "Configuration modules NVIDIA:"
        cat /etc/modprobe.d/nvidia.conf >> $REPORT_FILE

        # Vérifier les options recommandées
        if grep -q "NVreg_EnablePCIeGen3=0" /etc/modprobe.d/nvidia.conf; then
            success "Option NVreg_EnablePCIeGen3=0 configurée (stabilité multi-GPU)"
        else
            warning "Option NVreg_EnablePCIeGen3=0 non configurée (recommandée pour multi-GPU)"
        fi

        if grep -q "NVreg_UsePageAttributeTable=1" /etc/modprobe.d/nvidia.conf; then
            success "Option NVreg_UsePageAttributeTable=1 configurée (performance)"
        else
            warning "Option NVreg_UsePageAttributeTable=1 non configurée (recommandée pour performance)"
        fi
    else
        warning "Fichier de configuration modules NVIDIA non trouvé, création recommandée"
    fi

    # Vérifier le script de détection des GPUs
    if [ -f "/usr/local/bin/enable-all-gpus.sh" ]; then
        success "Script de réactivation des GPUs trouvé"
        if [ "$DETAILED" = true ]; then
            log "Contenu du script enable-all-gpus.sh:"
            cat /usr/local/bin/enable-all-gpus.sh >> $REPORT_FILE
        fi
    else
        warning "Script de réactivation des GPUs non trouvé, création recommandée"
    fi
}

check_nvidia_drivers() {
    section_header "PILOTES NVIDIA"

    # Vérifier l'installation des pilotes NVIDIA
    if command_exists nvidia-smi; then
        NVIDIA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        log "Version du pilote NVIDIA: $NVIDIA_VERSION"

        # Vérifier la compatibilité de la version
        if [ -n "$NVIDIA_VERSION" ]; then
            MAJOR_VERSION=$(echo "$NVIDIA_VERSION" | cut -d. -f1)
            if [ "$MAJOR_VERSION" -lt 450 ]; then
                warning "Version du pilote NVIDIA ($NVIDIA_VERSION) peut être obsolète pour CUDA récent"
            else
                success "Version du pilote NVIDIA compatible avec CUDA récent"
            fi
        fi

        # Vérifier les GPUs détectés par nvidia-smi
        GPU_COUNT_DRIVER=$(nvidia-smi --query-gpu=count --format=csv,noheader)

        if [ -z "$GPU_COUNT_DRIVER" ]; then
            error "Impossible d'obtenir le nombre de GPUs depuis nvidia-smi"
        else
            log "Nombre de GPUs détectés par le pilote NVIDIA: $GPU_COUNT_DRIVER"

            if [ "$GPU_COUNT_DRIVER" -eq 0 ]; then
                error "Aucun GPU détecté par le pilote NVIDIA"
            elif [ "$GPU_COUNT_DRIVER" -eq 1 ]; then
                warning "Un seul GPU détecté par le pilote NVIDIA"
            elif [ "$GPU_COUNT_DRIVER" -lt 8 ]; then
                warning "Seulement $GPU_COUNT_DRIVER GPUs détectés sur 8 attendus"
            else
                success "Tous les GPUs détectés par le pilote NVIDIA ($GPU_COUNT_DRIVER GPUs)"
            fi
        fi

        # Afficher les détails des GPUs détectés
        if [ "$GPU_COUNT_DRIVER" -gt 0 ]; then
            log "Détails des GPUs détectés:"
            nvidia-smi > /tmp/nvidia_smi.tmp
            cat /tmp/nvidia_smi.tmp >> $REPORT_FILE

            # Vérifier la capacité CUDA de chaque GPU
            for i in $(seq 0 $((GPU_COUNT_DRIVER-1))); do
                CUDA_CAPABILITY=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | sed -n "$((i+1))p")
                log "GPU $i: Capacité CUDA $CUDA_CAPABILITY"

                if [ -n "$CUDA_CAPABILITY" ]; then
                    MAJOR_CAP=$(echo "$CUDA_CAPABILITY" | cut -d. -f1)
                    if [ "$MAJOR_CAP" -lt 7 ]; then
                        warning "GPU $i a une capacité CUDA ($CUDA_CAPABILITY) qui peut limiter certaines fonctionnalités ML modernes"
                    fi
                fi
            done
        fi
    else
        error "Pilote NVIDIA (nvidia-smi) non trouvé"
    fi

    # Vérifier l'installation de CUDA
    if [ -d "/usr/local/cuda" ]; then
        if [ -f "/usr/local/cuda/version.txt" ]; then
            CUDA_VERSION=$(cat /usr/local/cuda/version.txt | grep "CUDA Version" | cut -d" " -f3)
            log "Version CUDA installée: $CUDA_VERSION"

            if [ "$CUDA_VERSION" \< "11.0" ]; then
                warning "Version CUDA installée peut être obsolète pour les frameworks ML récents"
            else
                success "Version CUDA compatible avec les frameworks ML récents"
            fi
        else
            log "CUDA installé mais fichier version.txt non trouvé"
        fi

        # Vérifier cuDNN
        if [ -d "/usr/local/cuda/include/cudnn.h" ] || [ -f "/usr/include/cudnn.h" ]; then
            success "cuDNN semble être installé"
        else
            warning "cuDNN ne semble pas être installé (requis pour certains frameworks ML)"
        fi
    else
        warning "Installation CUDA non trouvée dans /usr/local/cuda"
    fi
}

check_ml_environment() {
    section_header "ENVIRONNEMENT MACHINE LEARNING"

    # Vérifier l'installation de Python
    if command_exists python3; then
        PYTHON_VERSION=$(python3 --version 2>&1)
        log "Version Python: $PYTHON_VERSION"

        # Vérifier si virtualenv est utilisé
        if [ -d "/home/backtester/venv" ]; then
            log "Environnement virtuel trouvé: /home/backtester/venv"

            # Tester l'activation de l'environnement
            if su - backtester -c "source ~/venv/bin/activate && python -c 'import sys; print(sys.prefix)'" &>/dev/null; then
                success "L'environnement virtuel peut être activé"
            else
                warning "Problème avec l'activation de l'environnement virtuel"
            fi

            # Vérifier les packages importants si l'environnement est fonctionnel
            log "Vérification des packages Python essentiels..."

            # Créer un script Python temporaire pour vérifier les packages
            cat > /tmp/check_packages.py << EOF
import sys
import importlib.util

packages = [
    "numpy", "pandas", "matplotlib", "seaborn", "sklearn",
    "torch", "tensorflow", "jupyter", "ipykernel", "plotly"
]

results = {}
for package in packages:
    spec = importlib.util.find_spec(package)
    if spec is not None:
        try:
            module = importlib.import_module(package)
            version = getattr(module, "__version__", "version inconnue")
            results[package] = (True, version)
        except ImportError:
            results[package] = (True, "erreur import")
    else:
        results[package] = (False, "non installé")

for package, (installed, version) in results.items():
    status = "Installé" if installed else "NON INSTALLÉ"
    print(f"{package}: {status} ({version})")

# Vérifier CUDA pour PyTorch
try:
    import torch
    print(f"PyTorch CUDA: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"Nombre de GPUs PyTorch: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
except:
    print("Erreur lors de la vérification CUDA PyTorch")

# Vérifier CUDA pour TensorFlow
try:
    import tensorflow as tf
    print(f"TensorFlow GPUs: {len(tf.config.list_physical_devices('GPU'))}")
except:
    print("Erreur lors de la vérification CUDA TensorFlow")
EOF

            # Exécuter le script dans l'environnement virtuel
            PACKAGES_OUTPUT=$(su - backtester -c "source ~/venv/bin/activate && python /tmp/check_packages.py")

            echo "$PACKAGES_OUTPUT" > /tmp/packages_output.tmp
            cat /tmp/packages_output.tmp | while read line; do
                if echo "$line" | grep -q "NON INSTALLÉ"; then
                    warning "$line"
                else
                    log "$line"
                fi
            done

            # Vérifier l'accès CUDA via les frameworks ML
            if echo "$PACKAGES_OUTPUT" | grep -q "PyTorch CUDA: True"; then
                success "PyTorch a accès aux GPUs CUDA"

                # Vérifier le nombre de GPUs détectés par PyTorch
                PYTORCH_GPU_COUNT=$(echo "$PACKAGES_OUTPUT" | grep "Nombre de GPUs PyTorch:" | cut -d: -f2 | tr -d ' ')
                if [ "$PYTORCH_GPU_COUNT" == "0" ]; then
                    error "PyTorch ne détecte aucun GPU"
                elif [ "$PYTORCH_GPU_COUNT" == "1" ]; then
                    warning "PyTorch ne détecte qu'un seul GPU"
                else
                    success "PyTorch détecte $PYTORCH_GPU_COUNT GPUs"
                fi
            else
                error "PyTorch n'a pas accès aux GPUs CUDA"
            fi

            if echo "$PACKAGES_OUTPUT" | grep -q "TensorFlow GPUs:" | grep -v "0"; then
                success "TensorFlow a accès aux GPUs CUDA"
            else
                warning "TensorFlow ne détecte pas les GPUs CUDA"
            fi
        else
            warning "Aucun environnement virtuel trouvé dans /home/backtester/venv"
        fi
    else
        error "Python 3 n'est pas installé"
    fi
}

check_services() {
    section_header "SERVICES SYSTÈME"

    # Vérifier le service Jupyter
    if systemctl list-units --type=service | grep -q jupyter; then
        JUPYTER_STATUS=$(systemctl is-active jupyter.service)
        if [ "$JUPYTER_STATUS" == "active" ]; then
            success "Service Jupyter actif"
        else
            error "Service Jupyter inactif (status: $JUPYTER_STATUS)"
            log "Vérification des journaux Jupyter:"
            journalctl -u jupyter.service --no-pager -n 20 > /tmp/jupyter_log.tmp
            cat /tmp/jupyter_log.tmp >> $REPORT_FILE
        fi

        # Vérifier la configuration Jupyter
        if [ -f "/etc/jupyter/jupyter_notebook_config.py" ]; then
            log "Configuration Jupyter trouvée"

            # Vérifier les paramètres importants
            if grep -q "c.NotebookApp.ip = '0.0.0.0'" /etc/jupyter/jupyter_notebook_config.py; then
                success "Jupyter configuré pour accepter les connexions distantes"
            else
                warning "Jupyter peut ne pas accepter les connexions distantes"
            fi

            # Vérifier si un mot de passe est configuré
            if grep -q "c.NotebookApp.password = ''" /etc/jupyter/jupyter_notebook_config.py; then
                warning "Aucun mot de passe configuré pour Jupyter (non sécurisé)"
            else
                success "Mot de passe configuré pour Jupyter"
            fi
        else
            warning "Fichier de configuration Jupyter non trouvé"
        fi

        # Vérifier l'accès réseau
        JUPYTER_PORT=$(grep -o "c.NotebookApp.port = [0-9]*" /etc/jupyter/jupyter_notebook_config.py 2>/dev/null | cut -d= -f2 | tr -d ' ')
        if [ -z "$JUPYTER_PORT" ]; then
            JUPYTER_PORT=8888  # Port par défaut
        fi

        log "Port Jupyter configuré: $JUPYTER_PORT"

        # Vérifier si le port est ouvert dans le pare-feu
        if command_exists ufw && ufw status | grep -q "Status: active"; then
            if ufw status | grep -q "$JUPYTER_PORT/tcp"; then
                success "Port Jupyter ($JUPYTER_PORT) ouvert dans le pare-feu"
            else
                warning "Port Jupyter ($JUPYTER_PORT) peut être bloqué par le pare-feu"
            fi
        fi

        # Vérifier si Jupyter est accessible
        if command_exists curl; then
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:$JUPYTER_PORT 2>/dev/null | grep -q "200\|302"; then
                success "Jupyter est accessible localement sur le port $JUPYTER_PORT"
            else
                warning "Jupyter ne semble pas accessible localement sur le port $JUPYTER_PORT"
            fi
        fi
    else
        warning "Aucun service Jupyter trouvé"
    fi

    # Vérifier les services système importants
    for service in ssh cron systemd-timesyncd; do
        if systemctl list-units --type=service | grep -q "$service"; then
            SERVICE_STATUS=$(systemctl is-active $service.service)
            if [ "$SERVICE_STATUS" == "active" ]; then
                success "Service $service actif"
            else
                warning "Service $service inactif (status: $SERVICE_STATUS)"
            fi
        fi
    done

    # Vérifier chronyd/ntpd pour la synchronisation horaire
    if systemctl list-units --type=service | grep -q -E "chrony|ntp"; then
        success "Service de synchronisation horaire actif"
    else
        warning "Aucun service de synchronisation horaire (chrony/ntp) détecté"
    fi
}

check_system_optimization() {
    section_header "OPTIMISATION SYSTÈME"

    # Vérifier les limites ULIMIT importantes pour les environnements ML
    log "Limites système actuelles:"
    ULIMIT_N=$(ulimit -n)
    ULIMIT_M=$(ulimit -m 2>/dev/null || echo "unlimited")
    ULIMIT_V=$(ulimit -v 2>/dev/null || echo "unlimited")

    log "Nombre maximum de fichiers ouverts (nofile): $ULIMIT_N"
    log "Limite de mémoire maximum (memory): $ULIMIT_M"
    log "Taille de mémoire virtuelle maximum (virtual): $ULIMIT_V"

    if [ "$ULIMIT_N" -lt 65536 ]; then
        warning "La limite de fichiers ouverts est basse, recommandé: 65536+"
    else
        success "Limite de fichiers ouverts suffisante"
    fi

    # Vérifier les paramètres noyau pour ML
    log "Paramètres noyau pour ML:"

    VM_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A")

    if [ "$VM_SWAPPINESS" != "N/A" ]; then
        if [ "$VM_SWAPPINESS" -gt 10 ]; then
            warning "Valeur vm.swappiness élevée ($VM_SWAPPINESS), recommandé: 1-10 pour charge ML"
        else
            success "Valeur vm.swappiness optimisée pour charge ML"
        fi
    fi

    # Vérifier les paramètres de mémoire transparente huge pages
    TRANSPARENT_HUGEPAGES=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -o '\[[a-z]*\]' | tr -d '[]')

    if [ "$TRANSPARENT_HUGEPAGES" == "always" ]; then
        success "Transparent HugePages activées (optimal pour ML)"
    elif [ "$TRANSPARENT_HUGEPAGES" == "never" ]; then
        warning "Transparent HugePages désactivées (sous-optimal pour ML)"
    elif [ "$TRANSPARENT_HUGEPAGES" == "madvise" ]; then
        log "Transparent HugePages en mode madvise"
    fi

    # Vérifier le planificateur I/O pour le disque système
    SYSTEM_DISK=$(df / | awk 'NR==2 {print $1}' | sed 's/\/dev\///' | sed 's/[0-9]*$//')
    if [ -n "$SYSTEM_DISK" ] && [ -f "/sys/block/$SYSTEM_DISK/queue/scheduler" ]; then
        IO_SCHEDULER=$(cat /sys/block/$SYSTEM_DISK/queue/scheduler | grep -o '\[[a-z-]*\]' | tr -d '[]')
        log "Planificateur I/O pour le disque système: $IO_SCHEDULER"

        if [ "$IO_SCHEDULER" == "deadline" ] || [ "$IO_SCHEDULER" == "noop" ]; then
            success "Planificateur I/O optimal pour charge ML"
        elif [ "$IO_SCHEDULER" == "cfq" ]; then
            warning "Planificateur I/O sous-optimal pour charge ML (recommandé: deadline ou noop)"
        fi
    fi

    # Vérifier la présence de CPU mitigations (ralentissent le système)
    if grep -q 'mitigations=' /proc/cmdline; then
        CPU_MITIGATIONS=$(grep -o 'mitigations=[^ ]*' /proc/cmdline)
        warning "Mitigations CPU actives ($CPU_MITIGATIONS), peuvent réduire les performances"
    else
        log "Pas de mitigations CPU spécifiées dans les paramètres de démarrage"
    fi
}

check_network() {
    section_header "CONNECTIVITÉ RÉSEAU"

    # Obtenir les interfaces réseau
    NETWORK_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")

    log "Interfaces réseau détectées:"
    for interface in $NETWORK_INTERFACES; do
        IP_ADDRESS=$(ip -o -4 addr show dev $interface | awk '{print $4}' | cut -d/ -f1)
        log "  $interface: $IP_ADDRESS"
    done

    # Vérifier la connectivité réseau
    if ping -c 1 8.8.8.8 &>/dev/null; then
        success "Connectivité Internet via IP (ping 8.8.8.8)"
    else
        warning "Connectivité Internet via IP échouée (ping 8.8.8.8)"
    fi

    if ping -c 1 google.com &>/dev/null; then
        success "Résolution DNS fonctionnelle (ping google.com)"
    else
        warning "Problème de résolution DNS (ping google.com échoué)"
    fi

    # Vérifier la configuration du pare-feu
    if command_exists ufw; then
        UFW_STATUS=$(ufw status | grep "Status:" | awk '{print $2}')
        log "Statut pare-feu UFW: $UFW_STATUS"

        if [ "$UFW_STATUS" == "active" ]; then
            # Vérifier les règles importantes
            UFW_RULES=$(ufw status | grep -A 20 "To" | grep -E "22|SSH|8888|Jupyter")
            log "Règles pare-feu pour services essentiels:"
            echo "$UFW_RULES" >> $REPORT_FILE

            if ! echo "$UFW_RULES" | grep -q -E "22|SSH"; then
                warning "Aucune règle trouvée pour SSH dans le pare-feu"
            fi

            if ! echo "$UFW_RULES" | grep -q -E "8888|Jupyter"; then
                warning "Aucune règle trouvée pour Jupyter dans le pare-feu"
            fi
        fi
    else
        log "UFW n'est pas installé"
    fi

    # Vérifier les connexions réseaux actives
    if command_exists netstat; then
        LISTEN_PORTS=$(netstat -tuln | grep LISTEN)
        log "Ports en écoute:"
        echo "$LISTEN_PORTS" >> $REPORT_FILE

        # Vérifier Jupyter
        if echo "$LISTEN_PORTS" | grep -q ":8888"; then
            success "Port Jupyter (8888) en écoute"
        else
            warning "Port Jupyter (8888) non trouvé en écoute"
        fi

        # Vérifier SSH
        if echo "$LISTEN_PORTS" | grep -q ":22"; then
            success "Port SSH (22) en écoute"
        else
            warning "Port SSH (22) non trouvé en écoute"
        fi
    fi
}

check_gpu_performance() {
    section_header "PERFORMANCE GPU"

    if command_exists nvidia-smi; then
        # Vérifier l'état d'utilisation des GPUs
        log "État d'utilisation actuel des GPUs:"
        nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total --format=csv > /tmp/gpu_utilization.tmp
        cat /tmp/gpu_utilization.tmp >> $REPORT_FILE

        # Vérifier les performances maximales
        log "Vérification des modes de performance GPU..."
        nvidia-smi --query-gpu=index,name,clocks.max.memory,clocks.max.graphics --format=csv > /tmp/gpu_perf_modes.tmp
        cat /tmp/gpu_perf_modes.tmp >> $REPORT_FILE

        # Vérifier le mode de persistance (utile pour les charges ML)
        PERSISTENCE_MODE=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader | head -1)
        if [ "$PERSISTENCE_MODE" == "Enabled" ]; then
            success "Mode de persistance NVIDIA activé (optimal pour ML)"
        else
            warning "Mode de persistance NVIDIA désactivé (sous-optimal pour ML)"
        fi
    else
        error "nvidia-smi non disponible pour vérifier les performances GPU"
    fi

    # Vérifier benchmark PyTorch si disponible
    if [ -d "/home/backtester/venv" ] && [ "$DETAILED" = true ]; then
        log "Exécution d'un micro-benchmark GPU PyTorch..."

        # Créer un script benchmark temporaire
        cat > /tmp/gpu_benchmark.py << EOF
import torch
import time

def benchmark_gpu():
    if not torch.cuda.is_available():
        return "CUDA non disponible"

    n_gpu = torch.cuda.device_count()
    results = []

    for i in range(n_gpu):
        torch.cuda.set_device(i)

        # Taille des matrices: 5000x5000
        size = 5000

        # Créer deux matrices aléatoires sur GPU
        a = torch.randn(size, size, device='cuda')
        b = torch.randn(size, size, device='cuda')

        # Échauffer le GPU
        torch.matmul(a, b)
        torch.cuda.synchronize()

        # Chronométrer la multiplication
        start_time = time.time()
        torch.matmul(a, b)
        torch.cuda.synchronize()
        end_time = time.time()

        results.append({
            'gpu': i,
            'name': torch.cuda.get_device_name(i),
            'time': end_time - start_time,
            'size': size
        })

    return results

# Exécuter le benchmark
results = benchmark_gpu()
if isinstance(results, str):
    print(results)
else:
    print(f"Résultats du benchmark GPU PyTorch (matrices {results[0]['size']}x{results[0]['size']}):")
    for r in results:
        print(f"GPU {r['gpu']} ({r['name']}): {r['time']:.4f} secondes")
EOF

        # Exécuter le benchmark dans l'environnement virtuel
        BENCHMARK_OUTPUT=$(su - backtester -c "source ~/venv/bin/activate && python /tmp/gpu_benchmark.py")

        log "Résultats benchmark GPU:"
        echo "$BENCHMARK_OUTPUT" >> $REPORT_FILE

        # Analyser les résultats
        if echo "$BENCHMARK_OUTPUT" | grep -q "CUDA non disponible"; then
            error "Benchmark PyTorch: CUDA non disponible"
        else
            success "Benchmark PyTorch exécuté avec succès"
        fi
    fi
}

generate_recommendations() {
    section_header "RECOMMANDATIONS"

    if [ "$ISSUES_FOUND" -gt 0 ] || [ "$WARNINGS_FOUND" -gt 0 ]; then
        log "Voici les recommandations basées sur l'analyse :"

        # Recommandations pour configurations GPU
        if [ -f "/tmp/nvidia_pci.tmp" ] && [ -f "/tmp/nvidia_smi.tmp" ]; then
            PCI_GPU_COUNT=$(cat /tmp/nvidia_pci.tmp | wc -l)
            NVIDIA_GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null || echo "0")

            if [ "$PCI_GPU_COUNT" -gt "$NVIDIA_GPU_COUNT" ]; then
                echo "1. Problème de détection GPU: $NVIDIA_GPU_COUNT GPU(s) détecté(s) par le pilote sur $PCI_GPU_COUNT détecté(s) par PCI." >> $REPORT_FILE
                echo "   - Créez/mettez à jour le fichier /etc/modprobe.d/nvidia.conf avec:" >> $REPORT_FILE
                echo "     options nvidia NVreg_EnablePCIeGen3=0" >> $REPORT_FILE
                echo "     options nvidia NVreg_UsePageAttributeTable=1" >> $REPORT_FILE
                echo "     options nvidia NVreg_RegistryDwords=\"PerfLevelSrc=0x2222\"" >> $REPORT_FILE
                echo "" >> $REPORT_FILE
                echo "   - Ajoutez les paramètres suivants à GRUB via 'sudo nano /etc/default/grub':" >> $REPORT_FILE
                echo "     GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash pcie_aspm=off pci=noaer pci=realloc\"" >> $REPORT_FILE
                echo "     puis exécutez 'sudo update-grub'" >> $REPORT_FILE
                echo "" >> $REPORT_FILE
            fi
        fi

        # Recommandation pour script enable-all-gpus
        if ! [ -f "/usr/local/bin/enable-all-gpus.sh" ] && [ -f "/tmp/nvidia_pci.tmp" ]; then
            echo "2. Créez un script pour forcer la détection de tous les GPUs:" >> $REPORT_FILE
            echo "   sudo nano /usr/local/bin/enable-all-gpus.sh" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
            echo "   Avec le contenu suivant:" >> $REPORT_FILE
            echo "   #!/bin/bash" >> $REPORT_FILE
            echo "   for i in {0..7}; do" >> $REPORT_FILE

            # Générer dynamiquement les lignes du script basées sur les GPUs détectés
            cat /tmp/nvidia_pci.tmp | awk '{print $1}' | cut -d: -f1-2 | sort -u | while read pci_addr; do
                echo "     echo 1 > /sys/bus/pci/devices/0000:${pci_addr}.\$i/remove 2>/dev/null || true" >> $REPORT_FILE
            done

            echo "   done" >> $REPORT_FILE
            echo "   echo 1 > /sys/bus/pci/rescan" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
            echo "   Puis rendez-le exécutable:" >> $REPORT_FILE
            echo "   sudo chmod +x /usr/local/bin/enable-all-gpus.sh" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
        fi

        # Recommandation pour service Jupyter
        if systemctl list-units --type=service | grep -q jupyter && systemctl is-active jupyter.service != "active"; then
            echo "3. Le service Jupyter n'est pas actif. Essayez:" >> $REPORT_FILE
            echo "   sudo systemctl restart jupyter.service" >> $REPORT_FILE
            echo "   sudo systemctl status jupyter.service" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
        fi

        # Recommandation pour le nettoyage d'espace disque
        ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
        if [ "$ROOT_USAGE" -gt 80 ]; then
            echo "4. L'espace disque est faible (${ROOT_USAGE}%). Utilisez le script de nettoyage:" >> $REPORT_FILE
            echo "   sudo nano /usr/local/bin/clean-disk-space.sh" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
            echo "   Avec le contenu suivant:" >> $REPORT_FILE
            echo "   #!/bin/bash" >> $REPORT_FILE
            echo "   # Nettoyer les caches apt" >> $REPORT_FILE
            echo "   apt clean" >> $REPORT_FILE
            echo "   apt autoremove -y" >> $REPORT_FILE
            echo "   # Supprimer les fichiers temporaires" >> $REPORT_FILE
            echo "   rm -rf /var/cache/apt/archives/*.deb" >> $REPORT_FILE
            echo "   rm -rf /tmp/*" >> $REPORT_FILE
            echo "   find /var/log -type f -name \"*.gz\" -delete" >> $REPORT_FILE
            echo "   find /var/log -type f -name \"*.1\" -delete" >> $REPORT_FILE
            echo "   journalctl --vacuum-time=1d" >> $REPORT_FILE
            echo "" >> $REPORT_FILE

            if [ -d "/usr/local/cuda" ]; then
                echo "   # Nettoyer CUDA" >> $REPORT_FILE
                echo "   rm -rf /usr/local/cuda/doc" >> $REPORT_FILE
                echo "   rm -rf /usr/local/cuda/samples" >> $REPORT_FILE
                echo "   rm -rf /usr/local/cuda/extras" >> $REPORT_FILE
                echo "" >> $REPORT_FILE
            fi

            echo "   Puis rendez-le exécutable:" >> $REPORT_FILE
            echo "   sudo chmod +x /usr/local/bin/clean-disk-space.sh" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
        fi

        # Recommandation pour optimisation des performances
        echo "5. Pour optimiser les performances du système:" >> $REPORT_FILE
        echo "   - Activez le mode de persistance NVIDIA:" >> $REPORT_FILE
        echo "     sudo nvidia-smi -pm 1" >> $REPORT_FILE
        echo "" >> $REPORT_FILE
        echo "   - Optimisez swappiness:" >> $REPORT_FILE
        echo "     echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-sysctl.conf" >> $REPORT_FILE
        echo "     sudo sysctl -p /etc/sysctl.d/99-sysctl.conf" >> $REPORT_FILE
        echo "" >> $REPORT_FILE
    else
        success "Aucun problème ou avertissement détecté. Le système est correctement configuré."
    fi
}

###########################################
# EXÉCUTION PRINCIPALE
###########################################

# Initialisation du rapport
echo "Rapport de santé système - $(date)" > $REPORT_FILE
echo "Hostname: $HOSTNAME" >> $REPORT_FILE
echo "Kernel: $KERNEL" >> $REPORT_FILE
echo -e "\n----------------------------------------\n" >> $REPORT_FILE

# Vérification des privilèges root
check_root

# Exécution des vérifications
check_system_info
check_cpu_info
check_memory_info
check_disks
check_grub_config
check_gpu_passthrough
check_nvidia_drivers
check_ml_environment
check_services
check_system_optimization
check_network

# Exécuter le benchmark GPU uniquement si mode détaillé
if [ "$DETAILED" = true ]; then
    check_gpu_performance
fi

# Générer des recommandations
generate_recommendations

# Résumé final
section_header "RÉSUMÉ"
if [ "$ISSUES_FOUND" -eq 0 ] && [ "$WARNINGS_FOUND" -eq 0 ]; then
    success "Aucun problème détecté. L'environnement semble correctement configuré."
else
    log "Problèmes détectés: $ISSUES_FOUND"
    log "Avertissements: $WARNINGS_FOUND"
    warning "Des problèmes ont été détectés. Consultez les recommandations dans le rapport."
fi

log "Rapport de santé enregistré dans: $REPORT_FILE"

# Proposer un nettoyage si nécessaire
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$ROOT_USAGE" -gt 70 ]; then
    echo -e "\n${YELLOW}L'espace disque est assez utilisé (${ROOT_USAGE}%).${NC}"
    read -p "Voulez-vous exécuter le nettoyage automatique maintenant? [y/N]: " run_cleanup

    if [[ "$run_cleanup" =~ ^[Yy]$ ]]; then
        log "Exécution du nettoyage système..."

        # Nettoyer les caches apt
        apt clean
        apt autoremove -y

        # Supprimer les fichiers temporaires
        rm -rf /var/cache/apt/archives/*.deb
        rm -rf /tmp/*
        find /var/log -type f -name "*.gz" -delete
        find /var/log -type f -name "*.1" -delete
        journalctl --vacuum-time=1d

        # Nettoyer CUDA si présent
        if [ -d "/usr/local/cuda/doc" ]; then
            rm -rf /usr/local/cuda/doc
        fi
        if [ -d "/usr/local/cuda/samples" ]; then
            rm -rf /usr/local/cuda/samples
        fi
        if [ -d "/usr/local/cuda/extras" ]; then
            rm -rf /usr/local/cuda/extras
        fi

        log "Nettoyage terminé. Nouvel espace disque:"
        df -h /
    fi
fi

# Proposer un tuning si nécessaire
if [ "$ISSUES_FOUND" -gt 0 ] || [ "$WARNINGS_FOUND" -gt 0 ]; then
    echo -e "\n${YELLOW}Des problèmes ont été détectés qui pourraient bénéficier d'un tuning.${NC}"
    read -p "Voulez-vous appliquer les optimisations recommandées? [y/N]: " run_tuning

    if [[ "$run_tuning" =~ ^[Yy]$ ]]; then
        log "Application des optimisations recommandées..."

        # Créer le fichier de configuration NVIDIA si nécessaire
        if ! [ -f "/etc/modprobe.d/nvidia.conf" ]; then
            cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia NVreg_EnablePCIeGen3=0
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"
EOF
            success "Fichier de configuration NVIDIA créé"
        fi

        # Créer le script enable-all-gpus si nécessaire
        if ! [ -f "/usr/local/bin/enable-all-gpus.sh" ] && [ -f "/tmp/nvidia_pci.tmp" ]; then
            cat > /usr/local/bin/enable-all-gpus.sh << EOF
#!/bin/bash
# Script pour forcer la détection de tous les GPUs
# Exécuter avec sudo

echo "Forçage de la détection des GPUs..."

for i in {0..7}; do
EOF

            # Générer dynamiquement les lignes du script basées sur les GPUs détectés
            cat /tmp/nvidia_pci.tmp | awk '{print $1}' | cut -d: -f1-2 | sort -u | while read pci_addr; do
                echo "  echo 1 > /sys/bus/pci/devices/0000:${pci_addr}.\$i/remove 2>/dev/null || true" >> /usr/local/bin/enable-all-gpus.sh
            done

            cat >> /usr/local/bin/enable-all-gpus.sh << EOF
done

echo "Rescanning PCI bus..."
echo 1 > /sys/bus/pci/rescan

echo "Terminé. Vérifiez avec 'nvidia-smi'"
EOF
            chmod +x /usr/local/bin/enable-all-gpus.sh
            success "Script enable-all-gpus.sh créé"
        fi

        # Optimiser sysctl pour ML
        if ! grep -q "vm.swappiness=10" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
            echo "vm.swappiness=10" | tee -a /etc/sysctl.d/99-sysctl.conf > /dev/null
            sysctl -p /etc/sysctl.d/99-sysctl.conf
            success "Paramètre vm.swappiness optimisé"
        fi

        # Activer Transparent HugePages pour ML
        if [ -f "/sys/kernel/mm/transparent_hugepage/enabled" ]; then
            echo "always" > /sys/kernel/mm/transparent_hugepage/enabled
            success "Transparent HugePages activées"
        fi

        # Activer mode persistance NVIDIA
        if command_exists nvidia-smi; then
            nvidia-smi -pm 1
            success "Mode persistance NVIDIA activé"
        fi

        log "Optimisations terminées."
        warning "Un redémarrage est recommandé pour appliquer toutes les modifications."
    fi
fi

echo -e "\n${GREEN}Vérification de santé terminée.${NC}"
echo -e "Consultez le rapport détaillé: ${BLUE}$REPORT_FILE${NC}"
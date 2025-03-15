# Script PowerShell pour appliquer la configuration depuis le fichier .env
# À exécuter depuis la racine du projet MLENV

# Fonction pour l'affichage des messages
function Log-Message {
    param (
        [string]$Message,
        [string]$Type = "Info"
    )

    $Color = switch ($Type) {
        "Info" { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }

    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] [$Type] $Message" -ForegroundColor $Color
}

# Vérifier si le fichier .env existe
if (-not (Test-Path -Path ".env")) {
    Log-Message "Le fichier .env n'existe pas. Création à partir de .env.example..." "Warning"
    if (Test-Path -Path ".env.example") {
        Copy-Item -Path ".env.example" -Destination ".env"
        Log-Message "Fichier .env créé. Veuillez le modifier avec vos valeurs personnalisées puis réexécuter ce script." "Warning"
    } else {
        Log-Message "Fichier .env.example introuvable. Impossible de créer .env." "Error"
        exit 1
    }
    exit 0
}

# Fonction pour charger les variables d'environnement depuis le fichier .env
function Load-EnvFile {
    param (
        [string]$FilePath
    )

    Log-Message "Chargement des variables depuis $FilePath..."

    $EnvVars = @{}

    Get-Content -Path $FilePath | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $key, $value = $_ -split '=', 2
            $EnvVars[$key] = $value
        }
    }

    return $EnvVars
}

# Charger les variables d'environnement
$EnvVars = Load-EnvFile -FilePath ".env"

# Fonction pour remplacer les valeurs dans les fichiers
function Replace-TemplateValues {
    param (
        [string]$FilePath,
        [hashtable]$Variables
    )

    if (-not (Test-Path -Path $FilePath)) {
        Log-Message "Fichier non trouvé: $FilePath" "Warning"
        return
    }

    Log-Message "Application des variables à $FilePath..."

    $content = Get-Content -Path $FilePath -Raw

    foreach ($key in $Variables.Keys) {
        $placeholder = "{{$key}}"
        if ($content -match [regex]::Escape($placeholder)) {
            $content = $content -replace [regex]::Escape($placeholder), $Variables[$key]
            Log-Message "  Variable $key remplacée"
        }
    }

    Set-Content -Path $FilePath -Value $content
}

# Fonction pour configurer les fichiers Ansible
function Configure-AnsibleFiles {
    param (
        [hashtable]$EnvVars
    )

    # Vérifier si les répertoires existent
    if (-not (Test-Path -Path "ansible/inventory")) {
        New-Item -Path "ansible/inventory" -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path "ansible/inventory/group_vars")) {
        New-Item -Path "ansible/inventory/group_vars" -ItemType Directory -Force | Out-Null
    }

    # Créer ou mettre à jour le fichier hosts.yml
    $hostsContent = @"
---
all:
  hosts:
    proxmox:
      ansible_host: $($EnvVars['MLENV_HOST_IP'])
      ansible_user: $($EnvVars['MLENV_SSH_USER'])
      ansible_ssh_private_key_file: $($EnvVars['MLENV_SSH_KEY_PATH'])
  children:
    vms:
      hosts:
        backtesting:
          vm_id: $($EnvVars['MLENV_BACKTESTING_VM_ID'])
        machine_learning:
          vm_id: $($EnvVars['MLENV_ML_VM_ID'])
        webserver:
          vm_id: $($EnvVars['MLENV_WEB_VM_ID'])
    containers:
      hosts:
        database:
          container_id: $($EnvVars['MLENV_DB_CT_ID'])
        backup:
          container_id: $($EnvVars['MLENV_BACKUP_CT_ID'])
"@

    Set-Content -Path "ansible/inventory/hosts.yml" -Value $hostsContent
    Log-Message "Fichier hosts.yml créé/mis à jour" "Success"

    # Créer ou mettre à jour le fichier all.yml
    $allContent = @"
---
# Variables globales pour tous les hôtes

# Configuration de stockage
storage_path: "$($EnvVars['MLENV_STORAGE_PATH'])"
backup_path: "$($EnvVars['MLENV_BACKUP_PATH'])"
external_disk: "$($EnvVars['MLENV_EXTERNAL_DISK'])"

# Configuration GPU
gpu_ids: "$($EnvVars['MLENV_GPU_IDS'])"
backtesting_gpu_indices: [$($EnvVars['MLENV_BACKTESTING_GPU_INDICES'])]
ml_gpu_indices: [$($EnvVars['MLENV_ML_GPU_INDICES'])]

# Configuration des VMs
vm_memory: $($EnvVars['MLENV_VM_MEMORY'])
vm_cores: $($EnvVars['MLENV_VM_CORES'])

# Configuration des conteneurs
ct_memory: $($EnvVars['MLENV_CT_MEMORY'])
ct_cores: $($EnvVars['MLENV_CT_CORES'])

# Configuration des utilisateurs
backtesting_user: "$($EnvVars['MLENV_BACKTESTING_USER'])"
ml_user: "$($EnvVars['MLENV_ML_USER'])"
default_password: "$($EnvVars['MLENV_DEFAULT_PASSWORD'])"

# Configuration Jupyter
jupyter_port: $($EnvVars['MLENV_JUPYTER_PORT'])
jupyter_password_hash: "$($EnvVars['MLENV_JUPYTER_PASSWORD_HASH'])"

# Configuration PostgreSQL
db_name: "$($EnvVars['MLENV_DB_NAME'])"
db_user: "$($EnvVars['MLENV_DB_USER'])"
db_password: "$($EnvVars['MLENV_DB_PASSWORD'])"

# Configuration réseau
bridge_interface: "$($EnvVars['MLENV_BRIDGE_INTERFACE'])"
use_vlan: $($EnvVars['MLENV_USE_VLAN'].ToLower())
vlan_id: $($EnvVars['MLENV_VLAN_ID'])

# Options avancées
iommu_type: "$($EnvVars['MLENV_IOMMU_TYPE'])"
debug_mode: $($EnvVars['MLENV_DEBUG_MODE'].ToLower())
"@

    Set-Content -Path "ansible/inventory/group_vars/all.yml" -Value $allContent
    Log-Message "Fichier all.yml créé/mis à jour" "Success"
}

# Fonction pour configurer les fichiers Proxmox
function Configure-ProxmoxFiles {
    param (
        [hashtable]$EnvVars
    )

    # Configuration du script de passthrough GPU
    $gpuPassthroughPath = "proxmox/progressive-gpu-passthrough.sh"

    if (Test-Path -Path $gpuPassthroughPath) {
        $gpuPassthroughContent = Get-Content -Path $gpuPassthroughPath -Raw

        # Remplacer les IDs GPU
        $gpuPassthroughContent = $gpuPassthroughContent -replace 'options vfio-pci ids=10de:XXXX', "options vfio-pci ids=$($EnvVars['MLENV_GPU_IDS'])"

        # Mettre à jour le type d'IOMMU
        if ($EnvVars['MLENV_IOMMU_TYPE'] -eq "amd") {
            $gpuPassthroughContent = $gpuPassthroughContent -replace 'IOMMU_FLAG="intel_iommu=on"', 'IOMMU_FLAG="amd_iommu=on"'
        }

        Set-Content -Path $gpuPassthroughPath -Value $gpuPassthroughContent
        Log-Message "Script GPU passthrough configuré" "Success"
    } else {
        Log-Message "Script GPU passthrough non trouvé" "Warning"
    }

    # Configuration du script post-installation
    $postInstallPath = "proxmox/post-install.sh"

    if (Test-Path -Path $postInstallPath) {
        $postInstallContent = Get-Content -Path $postInstallPath -Raw

        # Remplacer le chemin de stockage
        $postInstallContent = $postInstallContent -replace '/mnt/vmstorage', $EnvVars['MLENV_STORAGE_PATH']

        Set-Content -Path $postInstallPath -Value $postInstallContent
        Log-Message "Script post-installation configuré" "Success"
    } else {
        Log-Message "Script post-installation non trouvé" "Warning"
    }
}

# Fonction pour configurer les fichiers de services
function Configure-ServiceFiles {
    param (
        [hashtable]$EnvVars
    )

    # Configuration du service Jupyter
    $jupyterServicePath = "config/systemd/jupyter.service"

    if (Test-Path -Path $jupyterServicePath) {
        $jupyterServiceContent = Get-Content -Path $jupyterServicePath -Raw

        # Remplacer l'utilisateur
        $jupyterServiceContent = $jupyterServiceContent -replace '%USER%', $EnvVars['MLENV_BACKTESTING_USER']

        Set-Content -Path $jupyterServicePath -Value $jupyterServiceContent
        Log-Message "Service Jupyter configuré" "Success"
    } else {
        Log-Message "Service Jupyter non trouvé" "Warning"
    }

    # Configuration Jupyter
    $jupyterConfigPath = "config/jupyter/jupyter_notebook_config.py"

    if (Test-Path -Path $jupyterConfigPath) {
        $jupyterConfigContent = Get-Content -Path $jupyterConfigPath -Raw

        # Mettre à jour le port et le mot de passe
        $jupyterConfigContent = $jupyterConfigContent -replace 'c.NotebookApp.port = 8888', "c.NotebookApp.port = $($EnvVars['MLENV_JUPYTER_PORT'])"
        $jupyterConfigContent = $jupyterConfigContent -replace "c.NotebookApp.password = ''", "c.NotebookApp.password = '$($EnvVars['MLENV_JUPYTER_PASSWORD_HASH'])'"

        Set-Content -Path $jupyterConfigPath -Value $jupyterConfigContent
        Log-Message "Configuration Jupyter mise à jour" "Success"
    } else {
        Log-Message "Configuration Jupyter non trouvée" "Warning"
    }
}

# Exécution des fonctions de configuration
try {
    Log-Message "Début de l'application de la configuration..." "Info"

    # Configurer les fichiers Ansible
    Configure-AnsibleFiles -EnvVars $EnvVars

    # Configurer les fichiers Proxmox
    Configure-ProxmoxFiles -EnvVars $EnvVars

    # Configurer les fichiers de services
    Configure-ServiceFiles -EnvVars $EnvVars

    Log-Message "Configuration appliquée avec succès!" "Success"
    Log-Message "N'oubliez pas de pousser ces modifications vers le dépôt Git si nécessaire." "Info"
} catch {
    Log-Message "Erreur lors de l'application de la configuration: $_" "Error"
    exit 1
}
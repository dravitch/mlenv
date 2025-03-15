#!/bin/bash
# Script pour créer la structure des rôles Ansible
# À exécuter depuis le répertoire ansible/

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Liste des rôles à créer
ROLES=(
    "common"
    "nvidia-drivers"
    "python-env"
    "jupyter"
    "backtesting"
    "ml-tools"
    "monitoring"
)

# Création du répertoire roles s'il n'existe pas
if [ ! -d "roles" ]; then
    log "Création du répertoire roles..."
    mkdir -p roles
fi

# Création de la structure pour chaque rôle
for role in "${ROLES[@]}"; do
    log "Création de la structure pour le rôle $role..."

    # Création des répertoires standard pour le rôle
    mkdir -p "roles/$role/"{tasks,handlers,templates,files,vars,defaults,meta}

    # Création du fichier main.yml dans tasks
    cat > "roles/$role/tasks/main.yml" << EOF
---
# Tâches principales pour le rôle $role
# Ce fichier sera appelé automatiquement lorsque le rôle est inclus
EOF

    # Création du fichier main.yml dans handlers
    cat > "roles/$role/handlers/main.yml" << EOF
---
# Handlers pour le rôle $role
EOF

    # Création du fichier main.yml dans defaults
    cat > "roles/$role/defaults/main.yml" << EOF
---
# Valeurs par défaut pour le rôle $role
EOF

    # Création du fichier main.yml dans vars
    cat > "roles/$role/vars/main.yml" << EOF
---
# Variables spécifiques pour le rôle $role
EOF

    # Création du fichier meta/main.yml
    cat > "roles/$role/meta/main.yml" << EOF
---
# Métadonnées pour le rôle $role
galaxy_info:
  role_name: $role
  author: PredatorX Admin
  description: Role for configuring $role on PredatorX
  license: MIT
  min_ansible_version: 2.9
  platforms:
    - name: Debian
      versions:
        - bullseye
    - name: Ubuntu
      versions:
        - jammy

dependencies: []
EOF

    success "Structure du rôle $role créée avec succès"
done

# Exemples de tâches pour certains rôles

# Rôle common
cat > "roles/common/tasks/main.yml" << 'EOF'
---
# Tâches pour le rôle common
- name: Installation des paquets de base
  apt:
    name:
      - htop
      - iotop
      - iftop
      - curl
      - wget
      - git
      - vim
      - tmux
      - screen
    state: present
    update_cache: yes

- name: Configuration du fuseau horaire
  timezone:
    name: Europe/Paris
EOF

# Rôle nvidia-drivers
cat > "roles/nvidia-drivers/tasks/main.yml" << 'EOF'
---
# Tâches pour le rôle nvidia-drivers
- name: Ajout du PPA pour les pilotes NVIDIA
  apt_repository:
    repo: ppa:graphics-drivers/ppa
    state: present
    update_cache: yes
  when: ansible_distribution == 'Ubuntu'

- name: Blacklist du pilote Nouveau
  copy:
    dest: /etc/modprobe.d/blacklist-nouveau.conf
    content: |
      blacklist nouveau
      options nouveau modeset=0
    mode: '0644'
  register: blacklist_nouveau

- name: Mise à jour de l'initramfs si Nouveau est blacklisté
  command: update-initramfs -u
  when: blacklist_nouveau.changed

- name: Installation du pilote NVIDIA
  apt:
    name: nvidia-driver-550
    state: present

- name: Vérification de l'installation NVIDIA
  command: nvidia-smi
  register: nvidia_smi
  changed_when: false
  failed_when: false
EOF

# Rôle python-env
cat > "roles/python-env/tasks/main.yml" << 'EOF'
---
# Tâches pour le rôle python-env
- name: Installation de Python et dépendances
  apt:
    name:
      - python3-pip
      - python3-dev
      - python3-venv
    state: present

- name: Création de l'environnement Python virtuel
  become: yes
  become_user: "{{ user_name }}"
  pip:
    name:
      - pip
      - wheel
      - setuptools
    state: latest
    virtualenv: "/home/{{ user_name }}/venv"
    virtualenv_command: python3 -m venv
EOF

# Rôle jupyter
cat > "roles/jupyter/tasks/main.yml" << 'EOF'
---
# Tâches pour le rôle jupyter
- name: Installation de JupyterLab
  become: yes
  become_user: "{{ user_name }}"
  pip:
    name:
      - jupyterlab
      - ipykernel
      - ipywidgets
    state: present
    virtualenv: "/home/{{ user_name }}/venv"

- name: Création du répertoire de configuration Jupyter
  file:
    path: /etc/jupyter
    state: directory
    mode: '0755'

- name: Configuration de Jupyter
  template:
    src: jupyter_notebook_config.py.j2
    dest: /etc/jupyter/jupyter_notebook_config.py
    mode: '0644'

- name: Configuration du service systemd pour Jupyter
  template:
    src: jupyter.service.j2
    dest: /etc/systemd/system/jupyter.service
    mode: '0644'

- name: Activation et démarrage du service Jupyter
  systemd:
    name: jupyter.service
    enabled: yes
    state: started
    daemon_reload: yes
EOF

success "Tous les rôles ont été créés avec succès!"
log "Pour utiliser ces rôles, modifiez le playbook principal (site.yml) pour inclure les rôles au lieu d'inclure les tâches."
log "Exemple: roles: ['common', 'nvidia-drivers', 'python-env', 'jupyter']"
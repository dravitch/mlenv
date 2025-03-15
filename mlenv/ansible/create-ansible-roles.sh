#!/bin/bash
# Script pour créer la structure des rôles Ansible
# À exécuter depuis le répertoire ansible/

# Couleurs pour les messages
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage des messages
log() {
    echo -e "\[\]\ \"
}

success() {
    echo -e "\[\]\ \"
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
for role in "\"; do
    log "Création de la structure pour le rôle \..."

    # Création des répertoires standard pour le rôle
    mkdir -p "roles/\/"{tasks,handlers,templates,files,vars,defaults,meta}

    # Création du fichier main.yml dans tasks
    cat > "roles/\/tasks/main.yml" << EOF
---
# Tâches principales pour le rôle \
# Ce fichier sera appelé automatiquement lorsque le rôle est inclus
EOF

    # Création du fichier main.yml dans handlers
    cat > "roles/\/handlers/main.yml" << EOF
---
# Handlers pour le rôle \
EOF

    # Création du fichier main.yml dans defaults
    cat > "roles/\/defaults/main.yml" << EOF
---
# Valeurs par défaut pour le rôle \
EOF

    # Création du fichier main.yml dans vars
    cat > "roles/\/vars/main.yml" << EOF
---
# Variables spécifiques pour le rôle \
EOF

    # Création du fichier meta/main.yml
    cat > "roles/\/meta/main.yml" << EOF
---
# Métadonnées pour le rôle \
galaxy_info:
  role_name: \
  author: PredatorX Admin
  description: Role for configuring \ on PredatorX
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

    success "Structure du rôle \ créée avec succès"
done

success "Tous les rôles ont été créés avec succès!"
log "Pour utiliser ces rôles, modifiez le playbook principal (site.yml) pour inclure les rôles au lieu d'inclure les tâches."
log "Exemple: roles: ['common', 'nvidia-drivers', 'python-env', 'jupyter']"

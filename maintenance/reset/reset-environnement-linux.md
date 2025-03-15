# Accéder au répertoire du projet
cd /chemin/vers/mlenv

# Supprimer les fichiers de suivi Git
rm -rf .git

# Supprimer tous les fichiers du projet (ATTENTION: cette opération est irréversible)
rm -rf *

# Réinitialiser Git
git init
git config user.name "Votre Nom"
git config user.email "votre.email@exemple.com"

# Créer le fichier .gitignore
cat > .gitignore << 'EOF'
# Fichiers système
.DS_Store
Thumbs.db

# Fichiers d'environnement
.env
.venv
env/
venv/
ENV/

# Fichiers de configuration personnels
config.local.yml

# Fichiers de compilation Python
*.py[cod]
*$py.class
__pycache__/

# Fichiers de logs
*.log
logs/

# Fichiers temporaires
tmp/
temp/
EOF
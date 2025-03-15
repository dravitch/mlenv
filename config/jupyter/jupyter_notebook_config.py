c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
# Générer un mot de passe sécurisé avec:
# python -c "from jupyter_server.auth import passwd; print(passwd('votre_mot_de_passe'))"
c.NotebookApp.password = ''  # Remplacer par le hash généré

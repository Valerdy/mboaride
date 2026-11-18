# Lancer MboaRide : les commandes

Ce guide tient en une page : toutes les commandes à taper sur un PC Windows pour faire
tourner le projet en entier (base de données, deux API, console web, application sur le
téléphone et l'émulateur). Les explications détaillées et le scénario d'essai complet
sont dans [demarrage-local.md](demarrage-local.md).

Toutes les commandes se tapent dans **PowerShell**, à la racine du dépôt (le dossier
`mboaride`).

---

## Une seule fois : préparer le PC

| À installer | Vérifier avec |
|---|---|
| PostgreSQL (service Windows démarré) | `Get-Service postgresql*` |
| Python 3.11 ou plus | `python --version` |
| Node.js 20 ou plus | `node --version` |
| Flutter | `flutter --version` |
| Outils Android (`adb`, émulateur) | `adb version` |

Puis :

1. Activer le **mode développeur de Windows** : Paramètres > Système > Espace
   développeurs. Sans lui, l'application ne compile pas (carte, GPS, appels).
2. Récupérer le code :

   ```powershell
   git clone https://github.com/Valerdy/mboaride.git
   cd mboaride
   git checkout develop
   ```

3. Créer le fichier de réglages et y mettre le mot de passe de l'utilisateur `postgres` :

   ```powershell
   Copy-Item .env.local.example .env.local
   notepad .env.local          # remplir PG_PASSWORD=..., enregistrer
   ```

   `.env.local` reste sur le PC : il n'est jamais envoyé sur GitHub.

4. Pour que le **code de vérification** arrive par e-mail (sinon il reste dans la fenêtre
   « MboaRide - API Node » et s'affiche dans l'application) :
   - sur le compte Gmail qui enverra les codes : Sécurité > Validation en deux étapes
     (l'activer), puis Sécurité > Mots de passe des applications > créer « MboaRide » ;
   - dans `.env.local`, remplir :

     ```
     SMTP_USER=adresse.qui.envoie@gmail.com
     SMTP_PASS=les 16 lettres du mot de passe d'application
     ```

   Au lancement, le script affiche « Codes de vérification envoyés par e-mail depuis ... ».

---

## À chaque fois : lancer le projet

### 1. Mettre le code à jour

```powershell
git pull origin develop
```

### 2. Allumer l'émulateur et brancher le téléphone

```powershell
& "$env:ANDROID_HOME\emulator\emulator.exe" -list-avds          # noms des émulateurs
& "$env:ANDROID_HOME\emulator\emulator.exe" -avd Pixel_7_Pro     # le démarrer (laisser la fenêtre ouverte)
```

Brancher le téléphone en USB, débogage USB autorisé, puis vérifier :

```powershell
adb devices          # chaque appareil doit être « device » (pas « unauthorized »)
```

### 3. Démarrer la base et les deux API

```powershell
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1
```

Le script fait tout seul :

1. il prépare Python et la base `mboaride` (création ou mise à niveau) ;
2. il ouvre deux fenêtres, **« MboaRide - API Node »** (port 8101) et **« MboaRide - API
   Python »** (port 8000). **Il faut les laisser ouvertes** : les fermer arrête MboaRide ;
3. il relie le téléphone et l'émulateur au PC.

Il se termine par « MboaRide tourne. ».

### 4. Ouvrir la console web

```powershell
Start-Process http://localhost:8000          # console des organisations
Start-Process http://localhost:8000/docs     # documentation de l'API
```

### 5. Lancer l'application

```powershell
cd frontend\mboaride_flutter_project
flutter devices          # doit lister emulator-5554 et le Pixel 7 Pro (2B241FDH3000YX)
```

Client, sur l'émulateur :

```powershell
flutter run -d emulator-5554 --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101
```

Chauffeur, sur le téléphone, le Pixel 7 Pro `2B241FDH3000YX` (dans un deuxième PowerShell,
même dossier) :

```powershell
flutter run -d 2B241FDH3000YX --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101 --dart-define=START=driver
```

`START=driver` ouvre directement l'espace conducteur après la connexion. Sans lui, le
conducteur y accède par le menu ☰ > « Espace conducteur ».

C'est prêt. Le code de vérification d'un nouveau compte s'affiche dans l'application et
dans la fenêtre « MboaRide - API Node ».

---

## Arrêter, relancer

```powershell
powershell -ExecutionPolicy Bypass -File scripts\arreter_tout.ps1     # arrêter les deux API
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1      # tout relancer
```

À relancer aussi quand une des deux fenêtres d'API a été fermée, ou après un `git pull`
qui modifie le serveur (la base est mise à niveau au passage).

Après avoir branché un appareil ou redémarré l'émulateur, il suffit de le relier au PC :

```powershell
powershell -ExecutionPolicy Bypass -File scripts\relier_android.ps1
```

Dans une fenêtre `flutter run` : `r` recharge l'application, `R` la redémarre, `q` la quitte.

---

## Essayer une course sans se déplacer

- Dans l'application, sur l'écran de course : choisir **« Simulation »** puis **« Lancer la
  simulation »**.
- Ou faire rouler le GPS de l'émulateur sur la vraie route :

  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\simuler_gps_emulateur.ps1 -De Kotto -A Bonanjo
  ```

---

## Lancer les tests

```powershell
cd frontend\mboaride_flutter_project; flutter test; cd ..\..         # application
cd agents; python -m pytest -q; cd ..                                # moteur d'agents
cd "backend\mboaride-api-node(1)"; npm test; cd ..\..                # API Node
```

Les tests de l'API Python ont besoin d'une base PostgreSQL de test : voir
`backend/tests/conftest.py`.

---

## Si ça ne marche pas

| Ce qu'on voit | Quoi faire |
|---|---|
| « Impossible de joindre le serveur » dans l'application | `scripts\relier_android.ps1`, puis vérifier que les deux fenêtres d'API sont ouvertes |
| `PG_PASSWORD est vide` au lancement | remplir `PG_PASSWORD` dans `.env.local` |
| une API ne démarre pas (port occupé) | `scripts\arreter_tout.ps1`, puis `scripts\lancer_tout.ps1` |
| téléphone `unauthorized` dans `adb devices` | accepter « Autoriser le débogage USB » sur le téléphone |
| « Building with plugins requires symlink support » | activer le mode développeur de Windows |
| « Votre session a expiré » | se reconnecter |
| le code de vérification n'arrive pas par e-mail | `SMTP_USER` / `SMTP_PASS` vides ou faux dans `.env.local` (mot de passe d'application, pas celui de Gmail), puis relancer ; regarder aussi les spams |
| aucune offre de trajet | voir le tableau « En cas de problème » de [demarrage-local.md](demarrage-local.md) |

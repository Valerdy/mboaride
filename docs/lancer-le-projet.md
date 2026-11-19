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

## À chaque fois : tout lancer en deux commandes

Brancher le téléphone en USB (débogage USB autorisé), puis, dans PowerShell à la racine
du dépôt :

```powershell
git pull origin develop
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1 -Apps
```

C'est tout. Le script fait, dans l'ordre :

1. il prépare Python et la base `mboaride` (création ou mise à niveau) ;
2. il ouvre deux fenêtres, **« MboaRide - API Node »** (port 8101) et **« MboaRide - API
   Python »** (port 8000). **Il faut les laisser ouvertes** : les fermer arrête MboaRide ;
3. il démarre l'émulateur s'il n'est pas déjà allumé (une à deux minutes) ;
4. il relie le téléphone et l'émulateur au PC (`adb reverse`) ;
5. il ouvre deux fenêtres **« MboaRide - Client »** et **« MboaRide - Chauffeur »** qui
   compilent et installent les applications :
   - **client sur le téléphone** branché ;
   - **chauffeur sur l'émulateur** (il s'ouvre directement sur l'espace conducteur).

La première compilation prend quelques minutes, les suivantes sont plus rapides. Les
applications s'ouvrent toutes seules sur chaque appareil.

Variantes :

```powershell
# Client sur l'émulateur et chauffeur sur le téléphone (services déjà lancés)
powershell -ExecutionPolicy Bypass -File scripts\lancer_apps.ps1 -Inverser

# Seulement les services, sans les applications
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1

# Seulement les applications (les services tournent déjà)
powershell -ExecutionPolicy Bypass -File scripts\lancer_apps.ps1
```

Si aucun téléphone n'est branché, les deux applications se lancent sur l'émulateur.

### Ouvrir la console web

```powershell
Start-Process http://localhost:8000/admin    # console d'administration de MboaRide
Start-Process http://localhost:8000          # console des organisations
Start-Process http://localhost:8000/docs     # documentation de l'API
```

La console d'administration se connecte avec un compte de l'application (même e-mail ou
téléphone, même mot de passe). Une seule fois, nommer le premier administrateur :

```powershell
backend\.venv\Scripts\python.exe scripts\creer_admin.py votre.adresse@gmail.com
```

Les autres membres de l'équipe se nomment ensuite depuis la console (menu « Équipe
MboaRide »), avec l'un des trois rôles :

| Rôle | Accès |
|---|---|
| Super admin | tout, y compris les paramètres et l'équipe |
| Support | utilisateurs (suspension), agréments (pièces à valider), trajets et courses, signalements, organisations, communication |
| Finance | paiements (remboursement, export CSV), finances |

Chaque action est tracée dans le « Journal d'audit », filtrable et exportable en CSV.

Les **paramètres** de la console (prix du carburant, commission, arrondi, prix minimum,
clôture automatique des courses, validité des pièces, validité du code de vérification)
s'appliquent en quelques secondes, sans relancer. Ils remplacent les variables
d'environnement correspondantes (`OTP_MINUTES`, `MBOARIDE_VALIDATION_AUTO_HEURES`).

**Pièces d'agrément.** Le conducteur dépose ses quatre pièces en photo depuis l'application.
Elles apparaissent dans la page « Agréments » de la console, où « Voir le fichier » ouvre la
photo ; l'administrateur valide ou refuse chaque pièce, et le conducteur est prévenu de
chaque décision. Les fichiers sont rangés dans `backend/stockage/` (jamais envoyé sur
GitHub) ; `MBOARIDE_STOCKAGE` change ce dossier. Les pièces des comptes créés avant cette
fonction n'ont pas de fichier : la console l'indique.

### Le code de vérification

Tant que `SMTP_USER` et `SMTP_PASS` sont vides dans `.env.local`, le code d'un nouveau
compte s'affiche dans l'application et dans la fenêtre « MboaRide - API Node ».

Le chauffeur est lancé avec `START=driver`, qui ouvre directement l'espace conducteur après
la connexion. Sans lui, le conducteur y accède par le menu ☰ > « Espace conducteur ».

---

## Arrêter, relancer

```powershell
powershell -ExecutionPolicy Bypass -File scripts\arreter_tout.ps1     # arrêter les deux API
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1 -Apps   # tout relancer
```

`arreter_tout.ps1` arrête les deux API. Les fenêtres « flutter run » se ferment avec `q`,
et l'émulateur avec la croix de sa fenêtre.

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
| une application ne se lance pas sur un appareil | `adb devices` doit le montrer en « device » ; sinon rebrancher le câble ou redémarrer l'émulateur, puis `scripts\lancer_apps.ps1` |
| une API ne démarre pas (port occupé) | `scripts\arreter_tout.ps1`, puis `scripts\lancer_tout.ps1` |
| téléphone `unauthorized` dans `adb devices` | accepter « Autoriser le débogage USB » sur le téléphone |
| « Building with plugins requires symlink support » | activer le mode développeur de Windows |
| « Votre session a expiré » | se reconnecter |
| le code de vérification n'arrive pas par e-mail | `SMTP_USER` / `SMTP_PASS` vides ou faux dans `.env.local` (mot de passe d'application, pas celui de Gmail), puis relancer ; regarder aussi les spams |
| aucune offre de trajet | voir le tableau « En cas de problème » de [demarrage-local.md](demarrage-local.md) |

# Lancer MboaRide de bout en bout sur un PC

Ce guide fait tourner toute l'application sur un seul PC Windows, avec une vraie base de
données, pour un essai à trois écrans :

| Écran | Rôle | Appareil |
|---|---|---|
| Application mobile, espace conducteur | le chauffeur publie son trajet et voit son équipage | téléphone Android branché en USB |
| Application mobile, espace passager | le client demande un trajet, voit les offres, réserve | émulateur Android (VS Code / Android Studio) |
| Console web | suivi, paiements, console entreprise, scénarios | navigateur du PC |

## Ce qui tourne

```
Téléphone (chauffeur) ─┐                      ┌─ API Node   :8101  inscription, connexion, itinéraires
Émulateur (client)  ───┼── adb reverse ──► PC ┤
Navigateur ────────────┘                      └─ API Python :8000  profil, demandes, offres du moteur
                                                                  d'agents, réservations, conducteur,
                                                                  console web (http://localhost:8000)
                      une seule base PostgreSQL « mboaride »
                      (schéma public : comptes Node ; schéma mboaride : métier)
```

L'API Node signe les jetons de session ; l'API Python les vérifie avec le même secret et
retrouve l'utilisateur dans la même base (voir `docs/decision-backend.md`, option C).
Après la connexion, l'application crée le profil métier (`POST /api/moi/profil`) ; un
e-mail d'une organisation connue (par exemple `@entreprise-a.cm`) rattache le compte à son
cercle de confiance.

## Prérequis

- PostgreSQL installé (service Windows) et le mot de passe de l'utilisateur `postgres` ;
- Python 3.11 ou plus, Node.js 20 ou plus, Flutter, les outils Android (`adb`) ;
- le téléphone en mode développeur, débogage USB autorisé ; un émulateur créé
  (Android Studio, Device Manager) ;
- le **mode développeur de Windows** activé (Paramètres > Système > Espace développeurs) :
  sans lui, Flutter ne peut pas créer les liens symboliques des extensions, et la carte,
  la position GPS ou l'appel d'un passager ne fonctionnent pas dans l'application.

## 1. Démarrer les serveurs

```powershell
powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1
```

Au premier lancement, le script crée `.env.local` à partir de `.env.local.example` et
s'arrête : y mettre `PG_PASSWORD`, puis relancer. Le script ensuite :

1. crée `backend\.venv` et installe les dépendances Python ;
2. crée la base `mboaride` (schéma, données d'exemple, données de la console) ou la met à niveau ;
3. ouvre une fenêtre « API Node » (port 8101) et une fenêtre « API Python » (port 8000) ;
4. relie chaque appareil Android branché au PC (`adb reverse`), pour que l'application
   joigne les deux API en `127.0.0.1` sans réglage réseau ni pare-feu.

Pour repartir d'une base vide : supprimer la base `mboaride` (pgAdmin ou `DROP DATABASE`)
et relancer le script.

## 2. Lancer les applications

Démarrer l'émulateur, brancher le téléphone, puis relier les deux au PC
(`scripts\relier_android.ps1`, inutile si ils étaient déjà là au lancement du script).
`flutter devices` donne leurs identifiants : `emulator-5554` pour l'émulateur et
`2B241FDH3000YX` pour le téléphone du chauffeur (Pixel 7 Pro).

```powershell
cd frontend\mboaride_flutter_project

# Chauffeur, sur le téléphone : l'espace conducteur s'ouvre après la connexion
flutter run -d 2B241FDH3000YX --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101 --dart-define=START=driver

# Client, sur l'émulateur
flutter run -d emulator-5554 --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101
```

Console web : http://localhost:8000 (documentation de l'API : http://localhost:8000/docs).

## 3. Scénario d'essai

**Chauffeur (téléphone)**

1. « Créer mon compte » : nom, e-mail `prenom@entreprise-a.cm`, téléphone, mot de passe
   (8 caractères). Le code de vérification s'affiche dans l'application (démonstration
   locale) et dans la fenêtre « API Node ».
2. Espace conducteur, carte « Agrément » : déposer les quatre pièces. En démonstration,
   chaque pièce est validée aussitôt (`MBOARIDE_AGREMENT_AUTO=1`) ; l'agrément devient actif.
3. « Mon véhicule » : modèle, immatriculation, places, consommation, confort.
4. Onglet « Trajets » : publier par exemple Logpom → Bonanjo, départ 06:50, du lundi au
   vendredi, 3 places, détour 3 km. Les lieux sont des quartiers connus
   (`GET /api/lieux`). Le **point de ramassage** est obligatoire : lieu exact et repère
   (« Station Total de Logpom, côté boulangerie »), consignes facultatives (« berline grise,
   je klaxonne deux fois ») et attente maximale. Il se modifie ensuite depuis l'équipage.

**Client (émulateur)**

5. Créer un compte avec un e-mail du même domaine (`@entreprise-a.cm`) : le client et le
   chauffeur sont collègues, donc dans le même cercle de confiance.
6. « Où allez-vous ? » : départ Kotto, arrivée Bonanjo, fenêtre d'arrivée 07:20 à 07:55,
   un jour où le chauffeur roule : « Aujourd'hui », « Demain » ou « Autre date » (calendrier,
   jusqu'à deux mois), prix maximal 800 FCFA.
7. L'offre du chauffeur apparaît, avec le prix détaillé, le véhicule et le point de
   ramassage : la choisir puis « Confirmer ». La place est retenue et l'écran de paiement
   s'ouvre.
8. Paiement (fictif), deux façons :
   - **portefeuille MboaRide** : « Recharger mon portefeuille » depuis un compte Mobile
     Money (code secret de 4 chiffres quelconque), puis « Payer avec mon portefeuille » ;
   - **Mobile Money** : enregistrer son compte une fois (MTN ou Orange, numéro de cet
     opérateur, titulaire), « Payer », code secret quelconque, « Valider ».

   Aucun montant n'est débité et le code n'est ni envoyé ni enregistré. Le trajet passe
   dans « Mes trajets », rubrique « Confirmés », avec le point de ramassage et le numéro du
   conducteur ; non payé, il reste « À confirmer » (« Payer » ou « Renoncer »).

**Retour au chauffeur**

9. Rouvrir l'espace conducteur : l'équipage montre le client qui a payé (nom, téléphone à
   appeler, note, lieu et heure de prise en charge ; un trajet non payé n'y apparaît pas).
   « Signaler un retard » et « Annuler le trajet » préviennent le client : la cloche de son
   application affiche la notification (elle interroge l'API toutes les 20 s).

**La course, sans se déplacer**

10. Chauffeur : « Démarrer la course ». Client : « Mes trajets » > « Suivre la course ».
    Sur chaque écran de course, choisir le mode :
    - « Simulation » puis « Lancer la simulation » : la position suit la route, accélérée
      vingt fois (une course en ville dure environ une minute) ;
    - « GPS » : la vraie position. Sur l'émulateur, la faire rouler le long de la route avec
      `powershell -File scripts\simuler_gps_emulateur.ps1 -De Kotto -A Bonanjo`
      (ou Extended controls > Location > Routes dans l'émulateur).
11. À moins de 80 m de la destination, l'écran de fin de course s'ouvre chez le client :
    « Merci d'avoir utilisé MboaRide », note de 1 à 5, commentaire, « Valider la fin de la
    course ». Le chauffeur, arrivé, suit les validations de son équipage.
12. Quand tous les passagers ont validé, le chauffeur reçoit dans son portefeuille le prix
    payé moins la commission MboaRide de 10 % (icône portefeuille de l'espace conducteur).
    Avec « Virement automatique vers Mobile Money », la somme part aussitôt vers son compte.
    En local (`MBOARIDE_SIMULATION=1`), la course peut démarrer avant son jour ; en
    production, seulement le jour du trajet, et une fin non validée l'est d'office 24 h
    après l'arrivée.

**Session**

13. L'application garde la session d'un lancement à l'autre. « Se déconnecter » (icône en
    haut de l'espace conducteur, menu ☰ ou profil côté client) ramène tout de suite à la
    connexion ; une session expirée est renouvelée, sinon l'application y ramène aussi.

**Console web (navigateur)**

14. Choisir le client dans « Connecté en tant que » : sa réservation et son paiement
    apparaissent.

## En cas de problème

| Symptôme | Cause probable |
|---|---|
| « Impossible de joindre le serveur » sur un appareil | `adb reverse` pas fait : `scripts\relier_android.ps1` |
| téléphone `unauthorized` dans `adb devices` | accepter « Autoriser le débogage USB » sur le téléphone |
| 403 « terminez votre inscription » | le profil métier n'a pas été créé : se reconnecter |
| aucune offre pour la demande | autre cercle (e-mails de domaines différents), jour où le chauffeur ne roule pas, fenêtre ou prix trop justes : l'écran « aucune offre » dit lequel |
| « Session expirée » | jeton de 12 h en local (`ACCESS_TOKEN_MINUTES`) : se reconnecter |
| « Building with plugins requires symlink support » | mode développeur de Windows désactivé (voir Prérequis) |
| l'écran de suivi reste « En attente de votre position » | localisation coupée ou refusée : l'autoriser, ou passer en « Simulation » |

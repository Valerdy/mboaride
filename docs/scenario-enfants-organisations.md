# Scénario simple : mes enfants et mes organisations

Ce scénario se joue en une quinzaine de minutes sur le téléphone ou l'émulateur, avec un second
compte pour l'entreprise. Il couvre trois choses :

1. **Mes organisations** : rejoindre l'école de ses enfants avec un code, voir ses cercles de confiance, en quitter un.
2. **Mes enfants** : créer un compte élève, réserver un voyage à son nom, suivre son journal, garder la main sur l'autorisation.
3. **Une entreprise** : l'administratrice invite un employé, qui rejoint le cercle de l'entreprise.

Le même parcours est rejoué automatiquement par `backend/tests/test_scenario_enfants_organisations.py`
(serveur) et `frontend/mboaride_flutter_project/test/features/scenario_enfants_organisations_test.dart`
(écrans) : s'ils passent, le scénario fonctionne.

## Les personnages

| Qui | Rôle dans le scénario | Compte |
|---|---|---|
| **Mireille**, parente | Elle a deux collégiens et en ajoute un troisième | à créer dans l'application, avec n'importe quelle adresse (par exemple `mireille@gmail.com`) |
| **Lina**, 13 ans | Sa fille, élève au Collège B | compte élève créé par Mireille (un enfant n'a pas de connexion) |
| **Hélène**, administratrice RH | Elle invite les employés de l'Entreprise A | compte de démonstration de la console web : « Hélène Ekwalla · admin RH » |
| **Paul**, employé | Il rejoint l'Entreprise A | adresse `paul@entreprise-a.cm` |
| **Un chauffeur** | Il fait le voyage Douala → Yaoundé | le voyage d'exemple du 20/11/2026 (Akwa → Yaoundé, 14 h), ou un voyage publié par le chauffeur |

Les données d'exemple contiennent : l'Entreprise A (domaine `entreprise-a.cm`, code `ENTA-2026`), le
**Collège B (Bonapriso)** (code **`COLB-2026`**) et le Campus C.

## Avant de commencer

Lancer le projet (`scripts\lancer_tout.ps1 -Apps`, voir [lancer-le-projet.md](lancer-le-projet.md)) et créer
le compte de Mireille dans l'application (menu « Créer mon compte », code de vérification affiché dans
l'application).

## Partie 1 · Mes organisations (Mireille)

1. Menu ☰ > **Mes organisations**. La liste est vide : « Vous ne faites partie d'aucune organisation ».
2. **Rejoindre avec un code**, saisir un code faux, par exemple `XXXX-0000` : l'application répond
   « Code inconnu : vérifiez-le auprès de l'organisation ».
3. Saisir `ENTA-2026` (le code de l'Entreprise A) : refusé. Une entreprise réservée à un nom de domaine
   ne s'ouvre pas avec un simple code ; il faut l'invitation de son administratrice (partie 3).
4. Saisir `COLB-2026` (en minuscules, cela marche aussi) : « Vous avez rejoint Collège B (Bonapriso) ».
   Le collège apparaît dans la liste, avec la mention « École · membre ».
5. Ressaisir `COLB-2026` : « Vous faites déjà partie de Collège B (Bonapriso) ».

**Ce que cela change.** Une organisation est un cercle de confiance : dans les offres de trajet, les
membres du même cercle sont étiquetés « Collègue », les autres « Partenaire » ou « Public vérifié ».

## Partie 2 · Mes enfants (Mireille)

6. Menu ☰ > **Mes enfants (scolaire)**. Les comptes déjà liés à Mireille sont listés avec leur
   établissement ; sur un compte neuf, la liste est vide.
7. **Ajouter un élève** : prénom `Lina`, âge `13`, établissement **Collège B (Bonapriso)** (liste
   déroulante, facultative). **Créer le compte**.
   - Un âge hors de 12 à 17 ans est refusé (« De 12 à 17 ans »).
   - MboaRide ne garde que le prénom et l'âge déclaré de l'élève.
8. La carte de Lina est verte : « Trajets autorisés. Vous recevez une notification au départ et à l'arrivée ».
9. **Réserver un voyage pour Lina** : l'écran des voyages interurbains s'ouvre, avec la mention
   « Place réservée pour Lina ». Choisir la date du voyage, le voyage Douala → Yaoundé, un point de montée,
   puis **Réserver**. Message : « Place confirmée · … ».
10. Retour sur la carte de Lina > **Voir le journal des trajets** : une ligne « Place confirmée pour le
    20/11 à 14:00 », avec le nom du chauffeur.
11. Les notifications de départ et d'arrivée sont simulées (US19 du document de vision) : dans le
    journal, **Simuler un trajet (démonstration)** produit « Lina est montée à bord à Akwa… » puis
    « Lina est arrivée à Yaoundé… ». Elles arrivent aussi dans la cloche du parent. Sans réservation
    confirmée, la simulation répond « Aucune réservation confirmée pour Lina ».

**Garder la main.**

12. Revenir sur la carte de Lina et **couper l'interrupteur** : « Trajets suspendus. Aucune réservation
    possible pour cet élève ». Le bouton « Réserver un voyage pour Lina » disparaît.
13. Même si quelqu'un contourne l'application, c'est la base de données qui refuse : une réservation pour
    un élève sans autorisation active est rejetée (« Autorisation parentale inactive »).
14. Rallumer l'interrupteur : la réservation redevient possible.

**Un autre parent ne voit rien.** Un second compte ne voit pas les enfants de Mireille et ne peut pas
réserver à leur nom.

## Partie 3 · Une entreprise (Hélène et Paul)

15. Dans le navigateur, ouvrir la console des organisations (http://localhost:8000), choisir le compte
    **Hélène Ekwalla · admin RH** dans « Compte », puis l'onglet **Console entreprise**.
16. Dans **Inviter des employés**, coller `paul@entreprise-a.cm` et `paul@autre.cm`, avec le service
    « Logistique », puis **Envoyer les invitations**.
    - `paul@entreprise-a.cm` reçoit une invitation et un lien unique, valable 30 jours.
    - `paul@autre.cm` est écartée : « hors du domaine entreprise-a.cm ».
    - Sans serveur d'e-mail configuré, l'envoi est simulé et le lien reste affiché pour être transmis.
17. Le **Suivi des invitations** montre Paul « envoyée » ; l'adoption par service s'affiche.
18. Paul ouvre le lien (`http://localhost:8000/rejoindre/…`). Il n'a pas de compte : il le crée depuis le
    lien (prénom, nom, téléphone, mot de passe), avec l'adresse de l'invitation, non modifiable.
    Autre possibilité : il crée directement son compte dans l'application avec `paul@entreprise-a.cm`,
    et rejoint l'Entreprise A grâce au nom de domaine de son adresse.
19. Dans l'application, Paul ouvre **Mes organisations** : « Entreprise A (Bonanjo) · Entreprise · membre ».
    Côté console, l'invitation passe à « acceptée » et l'adoption augmente.
20. Le lien ne sert qu'une fois. Paul peut **Quitter** l'entreprise (confirmation demandée) ;
    l'administratrice, elle, n'a pas ce bouton : une organisation ne reste jamais sans administrateur.

## Ce que le scénario vérifie

| Règle | Étape |
|---|---|
| Un code d'organisation est contrôlé, un domaine d'e-mail protège les entreprises | 2, 3, 5 |
| Un élève a de 12 à 17 ans, et son parent est le seul à le voir | 7, fin de la partie 2 |
| Sans autorisation parentale, aucune réservation, même contournée | 12, 13 |
| Le parent suit le départ et l'arrivée de son enfant | 10, 11 |
| Une invitation est nominative, limitée au domaine, à usage unique | 16, 18, 20 |
| Un administrateur ne peut pas quitter son organisation | 20 |

## Si ça ne marche pas

| Symptôme | Cause probable |
|---|---|
| Aucun voyage Douala → Yaoundé à la date choisie | le voyage d'exemple n'existe que le 20/11/2026 ; le chauffeur peut publier le sien (onglet « Trajets », « Interurbain ») |
| « Réserver un voyage pour Lina » absent | l'autorisation de Lina est coupée (étape 12) |
| Le code `COLB-2026` est refusé | la base n'est pas celle des données d'exemple : le code de chaque organisation est visible dans la console d'administration (page « Organisations ») |
| Pas d'onglet « Console entreprise » | le compte choisi n'est pas administrateur d'une organisation : prendre Hélène Ekwalla |

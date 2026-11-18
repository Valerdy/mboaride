# MboaRide · Diagrammes UML (Mermaid et PlantUML)

Diagrammes de conception de MboaRide, tirés du code réel : schéma PostgreSQL
(`backend/sql/01` à `10`), API Python (`backend/app`), API Node (authentification),
moteur multi-agents (`agents/mboaride_agents`) et application Flutter.

Les diagrammes sont en noir et blanc (thème Mermaid `neutral`), sauf les diagrammes de
séquence. Les diagrammes de cas d'utilisation (partie 5) sont en PlantUML, pour dessiner
les acteurs en bonhommes. Chaque bloc `mermaid` s'affiche directement sur GitHub, dans VS Code (extension
« Markdown Preview Mermaid Support ») ou sur https://mermaid.live (copier le contenu du
bloc, sans les lignes ```` ``` ````).

Sommaire :

1. [Modèle conceptuel de données (MCD)](#1-modèle-conceptuel-de-données-mcd)
2. [Diagrammes d'activité](#2-diagrammes-dactivité)
3. [Diagrammes de séquence](#3-diagrammes-de-séquence)
4. [Diagrammes de classes](#4-diagrammes-de-classes)
5. [Diagrammes de cas d'utilisation (PlantUML)](#5-diagrammes-de-cas-dutilisation)

---

## 1. Modèle conceptuel de données (MCD)

Entités et associations de la base `mboaride`, avec leurs cardinalités. Les associations
porteuses de données (appartenance, partenariat) sont représentées comme des entités
associatives. Notation : `||` exactement un, `o|` zéro ou un, `o{` zéro ou plusieurs.

```mermaid
%%{init: {"theme": "neutral"}}%%
erDiagram
    ORGANISATION {
        int id_organisation PK
        string nom
        string type_organisation "entreprise, etablissement_scolaire, campus, evenement"
        string ville
        string domaine_email UK
        string code_invitation UK
        boolean abonnement_actif
        int effectif
        decimal objectif_adoption
    }
    PARTENARIAT {
        int id_organisation_a PK, FK
        int id_organisation_b PK, FK
        date depuis_le
    }
    UTILISATEUR {
        int id_utilisateur PK
        string nom
        string prenom
        string telephone UK
        string email UK
        boolean est_conducteur
        string statut_agrement "non_demande, en_verification, actif, suspendu"
        string mode_reservation "autonome, manuel"
        string priorite "heure, prix"
        boolean accepte_collegues
        boolean accepte_partenaires
        boolean accepte_public
        boolean accepte_eleves
        int prix_min_fcfa
        int prix_max_defaut_fcfa
    }
    APPARTENANCE {
        int id_utilisateur PK, FK
        int id_organisation PK, FK
        string role "membre, administrateur"
        string service
        date date_adhesion
    }
    INVITATION {
        int id_invitation PK
        string email
        string jeton UK
        string statut "envoyee, acceptee, expiree, annulee"
        int relances
        datetime expire_le
    }
    COMPTE_NODE {
        int id_compte_node PK "users.id de l'API Node"
        int id_utilisateur FK, UK
        string lie_par "email, telephone, creation, manuel"
    }
    DOCUMENT_AGREMENT {
        int id_document PK
        string type_document "piece_identite, permis, casier_judiciaire, assurance"
        string statut "depose, valide, refuse, expire"
        date expire_le
    }
    VEHICULE {
        int id_vehicule PK
        string marque_modele
        string immatriculation UK
        int places_passagers
        decimal conso_l_100km
        boolean climatise
        boolean non_fumeur
    }
    COMPTE_ELEVE {
        int id_eleve PK
        string prenom
        int age_declare "12 à 17 ans"
        boolean autorisation_active
    }
    TRAJET {
        int id_trajet PK
        string type_trajet "urbain, interurbain"
        string depart_libelle
        string arrivee_libelle
        time heure_depart
        date date_unique "trajet ponctuel"
        string jours_semaine "trajet régulier, ex. 1111100"
        int places_offertes
        decimal detour_max_km
        int peage_fcfa
        string point_ramassage
        string consignes_ramassage
        int attente_max_min
        string statut "actif, annule, termine"
    }
    POINT_DEPART {
        int id_point PK
        int ordre_passage
        string libelle
        time heure_passage
    }
    INDISPONIBILITE_TRAJET {
        int id_trajet PK, FK
        date date_trajet PK
        string motif
    }
    DEMANDE {
        int id_demande PK
        string depart_libelle
        string arrivee_libelle
        time arrivee_au_plus_tot
        time arrivee_au_plus_tard
        date date_unique
        int prix_max_fcfa
        boolean clim_obligatoire
        string cercle_max "organisation, partenaires, public"
        string statut "ouverte, satisfaite, sans_equipage, annulee"
    }
    RESERVATION {
        int id_reservation PK
        date date_trajet
        time heure_prise_en_charge
        time heure_arrivee_estimee
        int prix_fcfa
        decimal detour_km
        string niveau_cercle
        string statut "confirmee, annulee, terminee"
        datetime fin_validee_le
    }
    PAIEMENT {
        int id_paiement PK
        int montant_fcfa
        int commission_fcfa "10 % du prix"
        string moyen "mobile_money, especes, portefeuille"
        string operateur "mtn, orange"
        string reference_transaction UK
        string statut "en_attente, reussi, echoue, rembourse"
        int tentatives "3 au plus"
        datetime verse_le "versé au conducteur"
        int montant_verse_fcfa
    }
    COMMISSION_MBOARIDE {
        int id_paiement PK, FK
        int montant_fcfa
        datetime preleve_le
    }
    EVALUATION {
        int id_evaluation PK
        int note "1 à 5"
        string commentaire
        boolean signalement_grave
    }
    COURSE {
        int id_trajet PK, FK
        date date_trajet PK
        string statut "en_cours, arrivee, reglee"
        datetime demarree_le
        datetime arrivee_le
        datetime reglee_le
    }
    COMPTE_MOBILE_MONEY {
        int id_compte PK
        string operateur "mtn, orange"
        string telephone
        string titulaire
        boolean par_defaut
    }
    PORTEFEUILLE {
        int id_utilisateur PK, FK
        int solde_fcfa "jamais négatif"
        boolean virement_auto
    }
    MOUVEMENT_PORTEFEUILLE {
        int id_mouvement PK
        string type "recharge, paiement, remboursement, gain, retrait"
        int montant_fcfa
        int solde_apres_fcfa
        string libelle
        string reference
    }
    NOTIFICATION {
        int id_notification PK
        string type "retard, annulation, course, fin_course, paiement, versement..."
        string message
        boolean lue
    }

    ORGANISATION ||--o{ APPARTENANCE : "regroupe"
    UTILISATEUR ||--o{ APPARTENANCE : "adhère à"
    ORGANISATION ||--o{ PARTENARIAT : "est partenaire (côté A)"
    ORGANISATION ||--o{ PARTENARIAT : "est partenaire (côté B)"
    ORGANISATION ||--o{ INVITATION : "envoie"
    UTILISATEUR ||--o{ INVITATION : "invite"
    UTILISATEUR |o--o{ INVITATION : "accepte"
    UTILISATEUR ||--o| COMPTE_NODE : "est authentifié par"
    UTILISATEUR ||--o{ DOCUMENT_AGREMENT : "dépose"
    UTILISATEUR ||--o{ VEHICULE : "possède"
    UTILISATEUR ||--o{ COMPTE_ELEVE : "est parent de"
    ORGANISATION |o--o{ COMPTE_ELEVE : "scolarise"
    UTILISATEUR ||--o{ TRAJET : "conduit"
    VEHICULE ||--o{ TRAJET : "est utilisé pour"
    TRAJET ||--o{ POINT_DEPART : "passe par"
    TRAJET ||--o{ INDISPONIBILITE_TRAJET : "est annulé le"
    UTILISATEUR ||--o{ DEMANDE : "formule"
    COMPTE_ELEVE |o--o{ DEMANDE : "concerne"
    ORGANISATION |o--o{ DEMANDE : "est rattachée à"
    DEMANDE ||--o{ RESERVATION : "aboutit à"
    TRAJET ||--o{ RESERVATION : "accueille"
    RESERVATION ||--o| PAIEMENT : "est réglée par"
    PAIEMENT ||--o| COMMISSION_MBOARIDE : "rapporte"
    RESERVATION ||--o{ EVALUATION : "est évaluée par"
    UTILISATEUR ||--o{ EVALUATION : "rédige"
    UTILISATEUR ||--o{ EVALUATION : "reçoit"
    TRAJET ||--o{ COURSE : "se déroule en"
    UTILISATEUR ||--o{ COMPTE_MOBILE_MONEY : "enregistre"
    UTILISATEUR ||--o| PORTEFEUILLE : "détient"
    PORTEFEUILLE ||--o{ MOUVEMENT_PORTEFEUILLE : "enregistre"
    RESERVATION |o--o{ MOUVEMENT_PORTEFEUILLE : "justifie"
    UTILISATEUR ||--o{ NOTIFICATION : "reçoit"
    RESERVATION |o--o{ NOTIFICATION : "concerne"
    COMPTE_ELEVE |o--o{ NOTIFICATION : "concerne"
```

Règles de gestion portées par la base (déclencheurs et contraintes) :

- RG1 : seul un conducteur à l'agrément actif publie un trajet ;
- RG2 : un trajet n'a pas plus de réservations confirmées que de places, pour une date donnée ;
- RG3 : un élève ne voyage que si son autorisation parentale est active ;
- RG4 : un signalement grave suspend l'agrément du conducteur évalué ;
- RG5 : une demande n'a qu'une réservation confirmée par date ;
- RG6 : un portefeuille n'est jamais négatif ; un paiement n'est versé au conducteur que s'il est réussi.

---

## 2. Diagrammes d'activité

Mermaid n'a pas de diagramme d'activité dédié : ils sont tracés en organigramme, avec un
couloir (sous-graphe) par acteur. Le cercle plein marque le début, le double cercle la fin,
les losanges les décisions.

### 2.1 Parcours complet d'un trajet partagé

De la publication par le conducteur au versement de son paiement.

```mermaid
%%{init: {"theme": "neutral"}}%%
flowchart TD
    debut((" ")) --> C1

    subgraph COND["Conducteur"]
        C1["Faire valider son agrément<br/>(4 pièces)"] --> C2["Enregistrer son véhicule"]
        C2 --> C3["Publier un trajet<br/>(jours, heure, places, détour,<br/>point de ramassage)"]
        C9["Démarrer la course"]
        C10["Prendre les passagers<br/>au point de ramassage"]
        C11["Déclarer l'arrivée"]
    end

    subgraph PASS["Passager"]
        P1["Se connecter"] --> P2["Demander un trajet<br/>(départ, arrivée, date,<br/>fenêtre d'arrivée, prix max, cercle)"]
        P3["Choisir une offre<br/>et confirmer le prix"]
        P4["Élargir le cercle, le budget<br/>ou la fenêtre"]
        P5["Payer<br/>(portefeuille ou Mobile Money)"]
        P6["Renoncer au trajet"]
        P7["Suivre la course sur la carte<br/>(GPS ou simulation)"]
        P8["Valider la fin de la course,<br/>noter et commenter"]
    end

    subgraph SYS["Système MboaRide (API et moteur d'agents)"]
        S1["Enregistrer la demande"] --> S2["Calculer les offres :<br/>cercle, jour, places, détour,<br/>horaires, prix"]
        S2 --> D1{"Offre<br/>confirmable ?"}
        D1 -->|non| S3["Diagnostic et suggestions"]
        D2{"Prix inchangé<br/>depuis l'affichage ?"}
        S4["Retenir la place<br/>et ouvrir un paiement en attente"]
        D3{"Paiement<br/>réussi ?"}
        D4{"Moins de<br/>3 tentatives ?"}
        S5["Libérer la place,<br/>rouvrir la demande"]
        S6["Ajouter le passager à l'équipage,<br/>prévenir le conducteur"]
        S7["Prévenir les passagers"]
        D5{"Arrivé à moins<br/>de 80 m ?"}
        D6{"Tous les passagers<br/>ont validé ?"}
        S8["Valider d'office<br/>après 24 h"]
        S9["Verser au portefeuille du conducteur<br/>le prix moins 10 % de commission"]
        D7{"Virement<br/>automatique ?"}
        S10["Virer vers son compte<br/>Mobile Money"]
    end

    C3 --> P1
    P2 --> S1
    S3 --> P4 --> P2
    D1 -->|oui| P3
    P3 --> D2
    D2 -->|non, nouveau prix| P3
    D2 -->|oui| S4
    S4 --> P5 --> D3
    D3 -->|non| D4
    D4 -->|oui| P5
    D4 -->|non| P6
    P6 --> S5 --> fin1(((" ")))
    D3 -->|oui| S6
    S6 --> C9 --> S7 --> C10 --> P7
    P7 --> D5
    D5 -->|non| P7
    D5 -->|oui| C11
    C11 --> P8 --> D6
    D6 -->|non| S8 --> D6
    D6 -->|oui| S9 --> D7
    D7 -->|oui| S10 --> fin(((" ")))
    D7 -->|non| fin

    style debut fill:#000,stroke:#000
    style fin fill:#000,stroke:#000
    style fin1 fill:#000,stroke:#000
```

### 2.2 Annulation d'un trajet par le conducteur et réaffectation (SR-47)

```mermaid
%%{init: {"theme": "neutral"}}%%
flowchart TD
    debut((" ")) --> A1

    subgraph COND["Conducteur"]
        A1["Annuler le trajet pour une date,<br/>avec un motif"]
    end

    subgraph SYS["Système MboaRide"]
        A2{"Déjà annulé<br/>ce jour-là ?"}
        A3["Marquer le trajet indisponible<br/>pour cette date"]
        A4["Annuler les réservations du jour"]
        A5["Pour chaque passager :<br/>prévenir et rembourser<br/>(portefeuille ou Mobile Money)"]
        A6["Rechercher les autres offres<br/>compatibles ce jour-là"]
        A7{"Mode de réservation<br/>du passager ?"}
        A8{"Une offre<br/>confirmable ?"}
        A9["Réserver automatiquement la meilleure<br/>(selon sa priorité : heure ou prix)"]
        A10["Rouvrir la demande"]
    end

    subgraph PASS["Passager"]
        B1["Reçoit : réaffecté à un nouveau<br/>conducteur, paiement à faire"]
        B2["Reçoit les offres disponibles<br/>et en choisit une"]
        B3["Reçoit : aucune offre pour l'instant,<br/>demande toujours ouverte"]
    end

    A1 --> A2
    A2 -->|oui| refus(((" ")))
    A2 -->|non| A3 --> A4 --> A5 --> A6 --> A7
    A7 -->|autonome| A8
    A8 -->|oui| A9 --> B1 --> fin(((" ")))
    A8 -->|non| A10
    A7 -->|manuel| A10
    A10 --> D{"Des offres<br/>disponibles ?"}
    D -->|oui| B2 --> fin
    D -->|non| B3 --> fin

    style debut fill:#000,stroke:#000
    style fin fill:#000,stroke:#000
    style refus fill:#000,stroke:#000
```

---

## 3. Diagrammes de séquence

Six séquences clés. Composants : l'application Flutter, l'API Node (authentification et
itinéraires, port 8101), l'API Python (métier, port 8000), la base PostgreSQL partagée, le
moteur de prix et d'itinéraires (`app/moteur.py`, qui réutilise `agents/mboaride_agents`)
et le système multi-agents.

### 3.1 Inscription, vérification du téléphone et connexion

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant App as Application Flutter
    participant Node as API Node (auth)
    participant Py as API Python
    participant DB as PostgreSQL

    U->>App: Nom, e-mail, téléphone, mot de passe
    App->>Node: POST /auth/register
    Node->>DB: INSERT users (non vérifié) et code à usage unique
    Node-->>App: 201 (code affiché en démonstration locale)
    U->>App: Saisit le code reçu par SMS
    App->>Node: POST /auth/verify-otp
    Node->>DB: users.is_verified = vrai, jeton de rafraîchissement
    Node-->>App: jeton d'accès (JWT) et jeton de rafraîchissement
    App->>Py: POST /api/moi/profil (Bearer JWT)
    Py->>Py: Vérifie la signature du JWT (secret partagé)
    Py->>DB: Crée l'utilisateur métier, compte_node, appartenance (domaine e-mail)
    Py-->>App: Profil (prénom, organisations, statut d'agrément)
    App->>App: Enregistre la session (stockage chiffré)

    Note over U,DB: Lancements suivants
    App->>Py: POST /api/moi/profil avec le jeton enregistré
    alt Jeton d'accès expiré (401)
        App->>Node: POST /auth/refresh
        Node-->>App: Nouveaux jetons (rafraîchissement à usage unique)
    end
    Py-->>App: Profil, ouverture de l'accueil
```

### 3.2 Demande de trajet et calcul des offres (prix détaillé)

```mermaid
sequenceDiagram
    autonumber
    actor P as Passager
    participant App as Application Flutter
    participant Py as API Python
    participant M as Moteur (prix et itinéraires)
    participant OSRM as OSRM (OpenStreetMap)
    participant DB as PostgreSQL

    P->>App: Départ, arrivée, date, fenêtre, prix max, cercle
    App->>Py: POST /api/demandes
    Py->>DB: INSERT demande (ou mise à jour d'une demande identique)
    Py-->>App: id de la demande
    App->>Py: GET /api/moi/demandes/:id/offres
    Py->>DB: Trajets actifs des autres conducteurs
    loop Pour chaque trajet actif
        Py->>DB: Niveau de cercle (organisation, partenaires, public)
        Py->>DB: Jour roulé, indisponibilité, places restantes
        Py->>M: horaires(trajet, demande)
        M->>OSRM: Détour imposé par ce passager
        OSRM-->>M: Distances et durées routières
        M-->>Py: Prise en charge, arrivée, détour (ou hors fenêtre)
        Py->>M: detail_prix(trajet, demande, passagers déjà à bord)
        M-->>Py: Prix arrondi à 25 FCFA, part conducteur, commission de 10 %
    end
    Py-->>App: Offres triées (confirmables d'abord, moins chères d'abord)
    alt Aucune offre confirmable
        App->>Py: GET /api/moi/demandes/:id/diagnostic
        Py-->>App: Motifs (cercle, horaires, budget...) et suggestions
        P->>App: Élargir le cercle
        App->>Py: POST /api/moi/demandes/:id/elargir
        Py-->>App: Offres ajoutées
    end
    App-->>P: Offres, prix détaillé, véhicule, point de ramassage
```

### 3.3 Négociation multi-agents (protocole Contract Net, FIPA-ACL)

```mermaid
sequenceDiagram
    autonumber
    participant PA as Agent passager
    participant CO as Agent coordinateur
    participant OA as Agent organisation
    participant D1 as Agent conducteur 1
    participant D2 as Agent conducteur 2

    PA->>CO: RIDE_REQUEST (REQUEST)
    CO->>OA: CIRCLE_QUERY (QUERY_IF) : le passager est-il membre ?
    OA-->>CO: CIRCLE_ANSWER (INFORM) : cercles autorisés
    CO-->>PA: REQUEST_AGREED (AGREE)
    Note over CO: Présélection bon marché des conducteurs<br/>(cercle, jour, places), sans itinéraire
    par Appel d'offres
        CO->>D1: CFP
    and
        CO->>D2: CFP
    end
    D1-->>PA: PROPOSAL (PROPOSE) : prix, prise en charge, détour
    D2-->>PA: DECLINE (REFUSE) : DETOUR_TOO_LONG
    PA->>PA: Classe les offres (score heure, prix, confort)
    alt Une offre acceptable
        PA->>D1: ACCEPT (ACCEPT_PROPOSAL)
        alt Place encore libre
            D1->>CO: BOOKING_CONFIRMED (CONFIRM)
            CO-->>PA: CREW_CONFIRMED (INFORM) : équipage
        else Plus de place
            D1-->>PA: BOOKING_FAILED (FAILURE)
        end
    else Aucune offre acceptable
        PA->>CO: NO_ACCEPTABLE_OFFER (INFORM)
        CO-->>PA: NO_CREW (FAILURE), ou nouvel appel élargi
    end
```

### 3.4 Réservation et paiement (portefeuille ou Mobile Money simulé)

```mermaid
sequenceDiagram
    autonumber
    actor P as Passager
    participant App as Application Flutter
    participant Py as API Python
    participant DB as PostgreSQL
    participant MM as Opérateur Mobile Money (simulé)

    P->>App: Confirmer l'offre au prix affiché
    App->>Py: POST /api/reservations (prix annoncé)
    Py->>Py: Réévalue le prix et les horaires
    alt Prix changé depuis l'affichage
        Py-->>App: 409 et nouveau prix (jamais débité en silence)
    else Prix identique
        Py->>DB: INSERT reservation (place retenue) et paiement en attente
        Py-->>App: id de réservation et de paiement
    end
    alt Paiement avec le portefeuille
        App->>Py: POST /api/paiements/:id/portefeuille
        Py->>DB: Verrouille le portefeuille, vérifie le solde
        alt Solde suffisant
            Py->>DB: Mouvement « paiement », paiement réussi
        else Solde insuffisant
            Py-->>App: 409 : montant manquant, proposer une recharge
        end
    else Paiement Mobile Money
        App->>Py: POST /api/paiements/:id/mobile-money (compte enregistré)
        Py->>DB: Paiement en attente, tentative + 1, référence MBR-...
        Py-->>App: Demande de validation envoyée au téléphone
        P->>App: Saisit son code secret (jamais envoyé)
        App->>Py: POST /api/paiements/:id/simulation-operateur
        Py->>MM: Réponse simulée de l'opérateur
        alt Validé
            Py->>DB: Paiement réussi
        else Refusé, solde insuffisant ou délai dépassé
            Py->>DB: Paiement échoué (3 tentatives au plus)
        end
    end
    Py->>DB: Notifications au passager et au conducteur
    Py-->>App: Reçu (référence, montant, part conducteur, commission)
    Note over Py,DB: L'argent reste chez MboaRide jusqu'à la fin de la course
```

### 3.5 Course, fin de course et versement au conducteur

```mermaid
sequenceDiagram
    autonumber
    actor C as Conducteur
    actor P as Passager
    participant AC as App conducteur
    participant AP as App passager
    participant GPS as Position (GPS ou simulation)
    participant Py as API Python
    participant DB as PostgreSQL

    C->>AC: Démarrer la course
    AC->>Py: POST /api/moi/conducteur/course/demarrer
    Py->>DB: INSERT course (en_cours), notifications aux passagers payés
    P->>AP: Mes trajets, puis Suivre la course
    AP->>Py: GET /api/moi/reservations/:id/suivi
    Py-->>AP: Point de ramassage, conducteur, véhicule, destination
    loop Toutes les positions
        GPS-->>AP: Nouvelle position (le long de la route)
        AP->>AP: Avance le repère, distance restante
    end
    AP->>AP: À moins de 80 m de la destination : écran de fin de course
    C->>AC: Arrivé à destination
    AC->>Py: POST /api/moi/conducteur/course/arrivee
    Py->>DB: course = arrivee, invitation à valider
    P->>AP: Note de 1 à 5 et commentaire
    AP->>Py: POST /api/moi/reservations/:id/fin-de-course
    Py->>DB: reservation terminee, fin_validee_le, INSERT evaluation
    Py->>DB: Notification au conducteur (note reçue)
    alt Tous les passagers payés ont validé
        Py->>DB: paiement.verse_le, commission_mboaride (10 %)
        Py->>DB: Mouvement « gain » dans le portefeuille du conducteur
        opt Virement automatique activé
            Py->>DB: Mouvement « retrait » vers son compte Mobile Money
        end
        Py->>DB: Notification « versement »
    else Validations manquantes
        Note over Py,DB: Validées d'office 24 h après l'arrivée
    end
    Py-->>AP: « Merci d'avoir utilisé MboaRide »
    loop Toutes les 5 s
        AC->>Py: GET /api/moi/conducteur/course
        Py-->>AC: Validations reçues, puis course réglée
    end
```

### 3.6 Retard ou annulation, et notifications

```mermaid
sequenceDiagram
    autonumber
    actor C as Conducteur
    participant AC as App conducteur
    participant Py as API Python
    participant DB as PostgreSQL
    participant AP as App passager
    participant OS as Notifications Android

    alt Retard
        C->>AC: Signaler un retard de 10 min
        AC->>Py: POST /api/moi/conducteur/retard
        Py->>DB: Nouvelle heure de prise en charge par passager, notification « retard »
    else Annulation
        C->>AC: Annuler le trajet du jour (motif)
        AC->>Py: POST /api/trajets/:id/annulations
        Py->>DB: Indisponibilité, réservations annulées, remboursements
        Py->>DB: Réaffectation (mode autonome) ou demande rouverte
        Py->>DB: Notifications « annulation », « reaffectation » ou « offres »
    end
    loop Toutes les 20 s (cloche de notifications)
        AP->>Py: GET /api/moi/notifications/resume
        Py-->>AP: Nombre de non lues et la plus récente
    end
    alt Nouvelle notification
        AP->>OS: Notification du téléphone (barre d'état)
        AP->>AP: Bandeau dans l'application, fermé après 5 s
    end
    AP->>Py: GET /api/moi/notifications (ouverture de la liste)
    Py->>DB: Marque les notifications comme lues
```

---

## 4. Diagrammes de classes

### 4.1 Domaine métier

Les classes persistantes (tables de la base) et les opérations exposées par l'API.
Conducteur et passager sont deux rôles d'un même `Utilisateur` : un passager devient
conducteur quand son agrément est actif.

```mermaid
%%{init: {"theme": "neutral"}}%%
classDiagram
    direction LR

    class Organisation {
        +int idOrganisation
        +String nom
        +TypeOrganisation type
        +String domaineEmail
        +String codeInvitation
        +inviter(emails) Invitation[]
        +adoption() Adoption
        +impact() Impact
    }
    class Utilisateur {
        +int idUtilisateur
        +String nom
        +String prenom
        +String telephone
        +String email
        +boolean estConducteur
        +StatutAgrement statutAgrement
        +ModeReservation modeReservation
        +int prixMinFcfa
        +deposerPiece(type) Agrement
        +publierTrajet(plan) Trajet
        +demanderTrajet(demande) Demande
        +niveauCercle(autre) Cercle
    }
    class Appartenance {
        +RoleOrganisation role
        +String service
        +Date dateAdhesion
    }
    class Vehicule {
        +String marqueModele
        +String immatriculation
        +int placesPassagers
        +double consoL100km
        +boolean climatise
    }
    class Trajet {
        +int idTrajet
        +TypeTrajet type
        +String depart
        +String arrivee
        +Time heureDepart
        +String joursSemaine
        +int placesOffertes
        +double detourMaxKm
        +String pointRamassage
        +String consignesRamassage
        +rouleLe(date) boolean
        +placesRestantes(date) int
        +annuler(date, motif) Annulation
        +signalerRetard(date, minutes) int
    }
    class Demande {
        +int idDemande
        +String depart
        +String arrivee
        +Time arriveeAuPlusTot
        +Time arriveeAuPlusTard
        +Date date
        +int prixMaxFcfa
        +Cercle cercleMax
        +StatutDemande statut
        +offres() Offre[]
        +diagnostic() Diagnostic
        +elargir(cercle) Offre[]
    }
    class Offre {
        +int prixFcfa
        +int commissionFcfa
        +int partConducteurFcfa
        +String priseEnCharge
        +String arriveeEstimee
        +double detourKm
        +boolean confirmable
    }
    class Reservation {
        +int idReservation
        +Date dateTrajet
        +int prixFcfa
        +StatutReservation statut
        +DateTime finValideeLe
        +renoncer() void
        +validerFin(note, commentaire) FinDeCourse
        +suivi() Suivi
    }
    class Paiement {
        +int montantFcfa
        +int commissionFcfa
        +MoyenPaiement moyen
        +String reference
        +StatutPaiement statut
        +int tentatives
        +DateTime verseLe
        +initierMobileMoney(compte) Recu
        +payerAvecPortefeuille() Recu
        +rembourser() void
    }
    class Course {
        +Date dateTrajet
        +StatutCourse statut
        +DateTime demarreeLe
        +DateTime arriveeLe
        +demarrer() void
        +declarerArrivee() void
        +reglerSiComplet() Versement
    }
    class Evaluation {
        +int note
        +String commentaire
        +boolean signalementGrave
    }
    class Portefeuille {
        +int soldeFcfa
        +boolean virementAuto
        +recharger(compte, montant) void
        +debiter(montant) void
        +crediter(montant) void
        +virer(compte, montant) void
    }
    class MouvementPortefeuille {
        +TypeMouvement type
        +int montantFcfa
        +int soldeApresFcfa
        +String libelle
    }
    class CompteMobileMoney {
        +Operateur operateur
        +String telephone
        +String titulaire
        +boolean parDefaut
        +verifierNumero() boolean
    }
    class Notification {
        +String type
        +String message
        +boolean lue
    }
    class CompteEleve {
        +String prenom
        +int ageDeclare
        +boolean autorisationActive
    }
    class DocumentAgrement {
        +TypeDocument type
        +StatutDocument statut
        +Date expireLe
    }

    class StatutReservation {
        <<enumeration>>
        CONFIRMEE
        ANNULEE
        TERMINEE
    }
    class StatutPaiement {
        <<enumeration>>
        EN_ATTENTE
        REUSSI
        ECHOUE
        REMBOURSE
    }
    class StatutCourse {
        <<enumeration>>
        EN_COURS
        ARRIVEE
        REGLEE
    }
    class Cercle {
        <<enumeration>>
        ORGANISATION
        PARTENAIRES
        PUBLIC
    }

    Organisation "1" -- "0..*" Appartenance
    Utilisateur "1" -- "0..*" Appartenance
    Organisation "0..*" -- "0..*" Organisation : partenaire de
    Utilisateur "1" *-- "0..4" DocumentAgrement : agrément
    Utilisateur "1" o-- "0..*" Vehicule : possède
    Utilisateur "1" o-- "0..*" CompteEleve : parent de
    Utilisateur "1" --> "0..*" Trajet : conduit
    Vehicule "1" <-- "0..*" Trajet : utilise
    Utilisateur "1" --> "0..*" Demande : formule
    Demande ..> Offre : calcule
    Offre --> Trajet
    Demande "1" --> "0..*" Reservation : aboutit à
    Trajet "1" --> "0..*" Reservation : accueille
    Reservation "1" *-- "0..1" Paiement
    Reservation "1" --> "0..*" Evaluation
    Trajet "1" *-- "0..*" Course : un jour donné
    Course ..> Paiement : verse
    Utilisateur "1" *-- "0..1" Portefeuille
    Portefeuille "1" *-- "0..*" MouvementPortefeuille
    Utilisateur "1" o-- "0..*" CompteMobileMoney
    Utilisateur "1" --> "0..*" Notification : reçoit
    Reservation --> StatutReservation
    Paiement --> StatutPaiement
    Course --> StatutCourse
    Demande --> Cercle
```

### 4.2 Moteur multi-agents et calcul du prix

Classes du paquet `agents/mboaride_agents`, réutilisées par l'API Python (`app/moteur.py`)
pour que le prix affiché soit celui que négocient les agents.

```mermaid
%%{init: {"theme": "neutral"}}%%
classDiagram
    direction TB

    class Agent {
        <<interface>>
        +agent_id String
        +handle(message) Message[]
    }
    class MessageBus {
        +register(agent) void
        +post(message, sent_at) Message
        +fingerprint() String
    }
    class Engine {
        +add_organization(agent) void
        +add_driver(agent) void
        +submit(request, at) String
        +choose(conversation, offer) void
        +widen(conversation) void
        +withdraw(conversation) void
        +cancel_trip(driver, at, reason) void
        +metrics() Metrics
    }
    class CoordinatorAgent {
        +cfp_fanout int
        +register_driver(listing) void
        +preselect(conversation, circle) String[]
    }
    class PassengerAgent {
        +request PassengerRequest
        +proposals() RankedOffer[]
        +start() Message
        +choose(offer_id) Message[]
        +widen() Message[]
        +withdraw() Message[]
    }
    class DriverAgent {
        +profile DriverProfile
        +trip DriverTrip
        +seats_free() int
        +on_accept(accept) Message
        +cancel_trip(reason) Message
    }
    class OrganizationAgent {
        +members Set
        +partners Set
        +refusal(query) String
    }
    class PassengerRequest {
        +origin Point
        +destination Point
        +window ArrivalWindow
        +max_price int
        +circle String
        +score_weights() ScoreWeights
    }
    class DriverTrip {
        +origin Point
        +destination Point
        +departure datetime
        +seats int
        +max_detour_m int
    }
    class DriverProfile {
        +approved boolean
        +circles Set
        +min_price int
        +comfort Set
    }
    class RankedOffer {
        +proposal Message
        +score Fraction
        +sort_key() tuple
    }
    class PricingPolicy {
        +fuel_price_per_l int
        +commission_rate Fraction
        +divisor_rule String
        +cost_basis String
        +commission_on_every_trip boolean
        +rounding_step int
        +min_fare int
    }
    class Quote {
        +price int
        +fuel_cost int
        +tolls int
        +divisor int
        +commission int
        +breakdown() dict
    }
    class RoutingService {
        <<interface>>
        +leg(a, b) tuple
        +detour(start, end, pickup, dropoff) Detour
    }
    class EstimatedRouting {
        +speed_kmh float
        +road_factor float
    }
    class OsrmRouting {
        +url String
        +fallback RoutingService
        +stats() dict
    }
    class Detour {
        +shared_distance_m int
        +detour_m int
        +pickup_offset_s int
        +trip_distance_m() int
    }
    class Point {
        +lat float
        +lon float
    }
    class Moteur {
        <<service>>
        +detail_prix(trajet, demande, niveau, places_reservees) DetailPrix
        +horaires(trajet, demande) tuple
        +distance_km(a, b) float
    }

    Engine *-- MessageBus
    Engine *-- CoordinatorAgent
    Engine o-- "0..*" PassengerAgent
    Engine o-- "0..*" DriverAgent
    Engine o-- "0..*" OrganizationAgent
    CoordinatorAgent ..|> Agent
    PassengerAgent ..|> Agent
    DriverAgent ..|> Agent
    OrganizationAgent ..|> Agent
    MessageBus --> "0..*" Agent : achemine
    PassengerAgent *-- PassengerRequest
    PassengerAgent *-- "0..*" RankedOffer
    DriverAgent *-- DriverTrip
    DriverAgent *-- DriverProfile
    DriverAgent ..> PricingPolicy : devis
    DriverAgent ..> RoutingService : détour
    PricingPolicy ..> Quote : quote()
    EstimatedRouting ..|> RoutingService
    OsrmRouting ..|> RoutingService
    OsrmRouting --> EstimatedRouting : repli
    RoutingService ..> Detour
    Detour ..> Point
    Moteur ..> PricingPolicy : PRODUCT_POLICY
    Moteur ..> RoutingService
```

---

## 5. Diagrammes de cas d'utilisation

Ces trois diagrammes sont en **PlantUML** et non en Mermaid : Mermaid ne sait pas dessiner
les acteurs UML en bonhommes. PlantUML produit la notation complète, en noir et blanc :
acteurs en bonhommes, cas d'utilisation en ovales dans le cadre du système, relations
« include » et « extend » en flèches pointillées, généralisation entre acteurs.

Pour les afficher, coller le bloc (de `@startuml` à `@enduml`) sur
https://www.planttext.com, ou ouvrir ce fichier dans VS Code avec l'extension
« PlantUML » (Alt+D sur le bloc).

### 5.1 Passager (et parent d'élève)

```plantuml
@startuml
left to right direction
skinparam monochrome true
skinparam shadowing false
skinparam packageStyle rectangle

actor "Passager" as Passager
actor "Parent d'élève" as Parent
actor "Opérateur\nMobile Money\n(simulé)" as Operateur

rectangle "Système MboaRide" {
  usecase "S'inscrire et\nse connecter" as UC1
  usecase "Demander un trajet" as UC2
  usecase "Consulter les offres\net le prix détaillé" as UC3
  usecase "Élargir le cercle\nde confiance" as UC4
  usecase "Réserver une offre" as UC5
  usecase "Payer le trajet" as UC6
  usecase "Recharger son\nportefeuille" as UC7
  usecase "Suivre la course\nsur la carte" as UC8
  usecase "Valider la fin\nde la course" as UC9
  usecase "Noter et commenter\nle conducteur" as UC10
  usecase "Renoncer à un trajet" as UC11
  usecase "Recevoir des\nnotifications" as UC12
  usecase "Réserver un voyage\ninterurbain" as UC13
  usecase "Gérer les comptes\nde ses enfants" as UC14
}

Parent --|> Passager

Passager -- UC1
Passager -- UC2
Passager -- UC5
Passager -- UC7
Passager -- UC8
Passager -- UC9
Passager -- UC11
Passager -- UC12
Passager -- UC13
Parent -- UC14

UC6 -- Operateur
UC7 -- Operateur

UC2 ..> UC3 : <<include>>
UC4 ..> UC3 : <<extend>>
UC5 ..> UC6 : <<include>>
UC9 ..> UC10 : <<include>>
UC13 ..> UC6 : <<include>>
@enduml
```

### 5.2 Conducteur

```plantuml
@startuml
left to right direction
skinparam monochrome true
skinparam shadowing false
skinparam packageStyle rectangle

actor "Conducteur" as Conducteur
actor "Agent conducteur\n(système multi-agents)" as Agent
actor "Passager" as Passager

rectangle "Système MboaRide" {
  usecase "Faire valider\nson agrément" as C1
  usecase "Enregistrer\nson véhicule" as C2
  usecase "Définir ses cercles\net ses règles" as C3
  usecase "Publier un trajet" as C4
  usecase "Préciser le point\nde ramassage" as C5
  usecase "Consulter son équipage" as C6
  usecase "Appeler un passager" as C7
  usecase "Démarrer et terminer\nla course" as C8
  usecase "Signaler un retard" as C9
  usecase "Annuler un trajet" as C10
  usecase "Réaffecter\nles passagers" as C11
  usecase "Évaluer ses passagers" as C12
  usecase "Recevoir ses gains\ndans son portefeuille" as C13
  usecase "Virer vers\nMobile Money" as C14
  usecase "Répondre aux demandes\n(proposer une place)" as C15
}

Conducteur -- C1
Conducteur -- C2
Conducteur -- C3
Conducteur -- C4
Conducteur -- C6
Conducteur -- C8
Conducteur -- C12
Conducteur -- C13
Conducteur -- C9
Conducteur -- C10
C15 -- Agent

C9 -- Passager
C10 -- Passager

C4 ..> C5 : <<include>>
C6 <.. C7 : <<extend>>
C10 ..> C11 : <<include>>
C13 <.. C14 : <<extend>>
C3 <.. C15 : <<include>>
@enduml
```

### 5.3 Organisation et console web

```plantuml
@startuml
left to right direction
skinparam monochrome true
skinparam shadowing false
skinparam packageStyle rectangle

actor "Administrateur\nd'organisation (RH)" as Admin
actor "Collaborateur invité" as Invite
actor "Équipe projet\n(démonstration)" as Equipe

rectangle "Console web MboaRide" {
  usecase "Inviter des collaborateurs\npar e-mail" as O1
  usecase "Relancer une invitation" as O2
  usecase "Accepter une invitation\net s'inscrire" as O3
  usecase "Suivre l'adoption\npar service" as O4
  usecase "Consulter les économies\net le CO2 évité" as O5
  usecase "Exporter l'impact\nen CSV" as O6
  usecase "Rejouer un scénario\nde démonstration" as O7
  usecase "Lancer le banc de mesure\ndu moteur d'agents" as O8
}

Admin -- O1
Admin -- O4
Admin -- O5
Invite -- O3
Equipe -- O7
Equipe -- O8

O2 ..> O1 : <<extend>>
O6 ..> O5 : <<extend>>
@enduml
```

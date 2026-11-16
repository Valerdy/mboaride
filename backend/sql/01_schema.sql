-- =====================================================================
-- MboaRide · Base de données (PostgreSQL 14 ou plus récent)
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- Script de création : tables, contraintes, index, déclencheurs, vues.
-- Les positions sont stockées en latitude et longitude ; la version cible
-- peut les convertir en géométries PostGIS sans changer le modèle.
-- =====================================================================

DROP SCHEMA IF EXISTS mboaride CASCADE;
CREATE SCHEMA mboaride;
SET search_path TO mboaride;

-- ---------------------------------------------------------------------
-- 1. Organisations et cercles de confiance
-- ---------------------------------------------------------------------
CREATE TABLE organisation (
    id_organisation     SERIAL PRIMARY KEY,
    nom                 VARCHAR(120) NOT NULL,
    type_organisation   VARCHAR(24)  NOT NULL
        CHECK (type_organisation IN ('entreprise', 'etablissement_scolaire', 'campus', 'evenement')),
    ville               VARCHAR(60)  NOT NULL DEFAULT 'Douala',
    domaine_email       VARCHAR(120) UNIQUE,
    code_invitation     VARCHAR(12)  NOT NULL UNIQUE,
    abonnement_actif    BOOLEAN      NOT NULL DEFAULT FALSE,
    tarif_mensuel_fcfa  INTEGER      NOT NULL DEFAULT 0 CHECK (tarif_mensuel_fcfa >= 0),
    cree_le             TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Association réflexive « être partenaire » : chaque paire est stockée une seule fois.
CREATE TABLE partenariat (
    id_organisation_a   INTEGER NOT NULL REFERENCES organisation ON DELETE CASCADE,
    id_organisation_b   INTEGER NOT NULL REFERENCES organisation ON DELETE CASCADE,
    depuis_le           DATE    NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id_organisation_a, id_organisation_b),
    CHECK (id_organisation_a < id_organisation_b)
);

-- ---------------------------------------------------------------------
-- 2. Utilisateurs, appartenance, agrément
-- ---------------------------------------------------------------------
CREATE TABLE utilisateur (
    id_utilisateur        SERIAL PRIMARY KEY,
    nom                   VARCHAR(60)  NOT NULL,
    prenom                VARCHAR(60)  NOT NULL,
    telephone             VARCHAR(20)  NOT NULL UNIQUE,
    email                 VARCHAR(120) UNIQUE,
    mot_de_passe_hache    VARCHAR(255) NOT NULL,
    est_conducteur        BOOLEAN      NOT NULL DEFAULT FALSE,
    statut_agrement       VARCHAR(16)  NOT NULL DEFAULT 'non_demande'
        CHECK (statut_agrement IN ('non_demande', 'en_verification', 'actif', 'suspendu')),
    date_agrement         DATE,
    mode_reservation      VARCHAR(10)  NOT NULL DEFAULT 'manuel'
        CHECK (mode_reservation IN ('autonome', 'manuel')),
    priorite              VARCHAR(6)   NOT NULL DEFAULT 'heure'
        CHECK (priorite IN ('heure', 'prix')),
    accepte_partenaires   BOOLEAN      NOT NULL DEFAULT TRUE,
    accepte_public        BOOLEAN      NOT NULL DEFAULT FALSE,
    souhaite_clim         BOOLEAN      NOT NULL DEFAULT FALSE,
    souhaite_non_fumeur   BOOLEAN      NOT NULL DEFAULT FALSE,
    souhaite_silence      BOOLEAN      NOT NULL DEFAULT FALSE,
    consentement_position BOOLEAN      NOT NULL DEFAULT FALSE,
    cree_le               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (statut_agrement <> 'actif' OR date_agrement IS NOT NULL)
);

CREATE TABLE appartenance (
    id_utilisateur   INTEGER     NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    id_organisation  INTEGER     NOT NULL REFERENCES organisation ON DELETE CASCADE,
    role             VARCHAR(14) NOT NULL DEFAULT 'membre'
        CHECK (role IN ('membre', 'administrateur')),
    date_adhesion    DATE        NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id_utilisateur, id_organisation)
);

CREATE TABLE document_agrement (
    id_document      SERIAL PRIMARY KEY,
    id_utilisateur   INTEGER     NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    type_document    VARCHAR(20) NOT NULL
        CHECK (type_document IN ('piece_identite', 'permis', 'casier_judiciaire', 'assurance')),
    statut           VARCHAR(10) NOT NULL DEFAULT 'depose'
        CHECK (statut IN ('depose', 'valide', 'refuse', 'expire')),
    chemin_fichier   VARCHAR(255) NOT NULL,
    depose_le        TIMESTAMPTZ NOT NULL DEFAULT now(),
    expire_le        DATE,
    UNIQUE (id_utilisateur, type_document)
);

-- ---------------------------------------------------------------------
-- 3. Véhicules et comptes élèves
-- ---------------------------------------------------------------------
CREATE TABLE vehicule (
    id_vehicule       SERIAL PRIMARY KEY,
    id_proprietaire   INTEGER      NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    marque_modele     VARCHAR(80)  NOT NULL,
    immatriculation   VARCHAR(15)  NOT NULL UNIQUE,
    places_passagers  SMALLINT     NOT NULL CHECK (places_passagers BETWEEN 1 AND 8),
    conso_l_100km     NUMERIC(4,1) NOT NULL DEFAULT 8.0 CHECK (conso_l_100km > 0),
    climatise         BOOLEAN      NOT NULL DEFAULT FALSE,
    non_fumeur        BOOLEAN      NOT NULL DEFAULT TRUE,
    accepte_bagages   BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (id_vehicule, id_proprietaire)
);

-- Minimisation des données : prénom et âge déclaré seulement.
CREATE TABLE compte_eleve (
    id_eleve             SERIAL PRIMARY KEY,
    id_parent            INTEGER     NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    id_etablissement     INTEGER     REFERENCES organisation ON DELETE SET NULL,
    prenom               VARCHAR(60) NOT NULL,
    age_declare          SMALLINT    NOT NULL CHECK (age_declare BETWEEN 12 AND 17),
    autorisation_active  BOOLEAN     NOT NULL DEFAULT TRUE,
    notifier_depart      BOOLEAN     NOT NULL DEFAULT TRUE,
    notifier_arrivee     BOOLEAN     NOT NULL DEFAULT TRUE,
    notifier_retard      BOOLEAN     NOT NULL DEFAULT TRUE,
    cree_le              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id_eleve, id_parent)
);

-- ---------------------------------------------------------------------
-- 4. Trajets proposés et demandes de trajet
-- ---------------------------------------------------------------------
-- jours_semaine : 7 caractères du lundi au dimanche, 1 = trajet ce jour-là.
CREATE TABLE trajet (
    id_trajet            SERIAL PRIMARY KEY,
    id_conducteur        INTEGER      NOT NULL REFERENCES utilisateur,
    id_vehicule          INTEGER      NOT NULL,
    type_trajet          VARCHAR(12)  NOT NULL DEFAULT 'urbain'
        CHECK (type_trajet IN ('urbain', 'interurbain')),
    depart_libelle       VARCHAR(120) NOT NULL,
    depart_lat           NUMERIC(9,6) NOT NULL CHECK (depart_lat BETWEEN -90 AND 90),
    depart_lon           NUMERIC(9,6) NOT NULL CHECK (depart_lon BETWEEN -180 AND 180),
    arrivee_libelle      VARCHAR(120) NOT NULL,
    arrivee_lat          NUMERIC(9,6) NOT NULL CHECK (arrivee_lat BETWEEN -90 AND 90),
    arrivee_lon          NUMERIC(9,6) NOT NULL CHECK (arrivee_lon BETWEEN -180 AND 180),
    heure_depart         TIME         NOT NULL,
    date_unique          DATE,
    jours_semaine        CHAR(7)      CHECK (jours_semaine ~ '^[01]{7}$' AND jours_semaine <> '0000000'),
    places_offertes      SMALLINT     NOT NULL CHECK (places_offertes BETWEEN 1 AND 8),
    detour_max_km        NUMERIC(4,1) NOT NULL DEFAULT 3.0 CHECK (detour_max_km >= 0),
    peage_fcfa           INTEGER      NOT NULL DEFAULT 0 CHECK (peage_fcfa >= 0),
    ouvert_partenaires   BOOLEAN      NOT NULL DEFAULT TRUE,
    ouvert_public        BOOLEAN      NOT NULL DEFAULT FALSE,
    statut               VARCHAR(8)   NOT NULL DEFAULT 'actif'
        CHECK (statut IN ('actif', 'annule', 'termine')),
    cree_le              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- un trajet est soit ponctuel (date unique), soit régulier (jours de la semaine)
    CHECK ((date_unique IS NULL) <> (jours_semaine IS NULL)),
    -- le véhicule doit appartenir au conducteur
    FOREIGN KEY (id_vehicule, id_conducteur) REFERENCES vehicule (id_vehicule, id_proprietaire)
);

-- Points de départ supplémentaires d'un voyage interurbain (Akwa, Ndokoti...).
CREATE TABLE point_depart (
    id_point        SERIAL PRIMARY KEY,
    id_trajet       INTEGER      NOT NULL REFERENCES trajet ON DELETE CASCADE,
    ordre_passage   SMALLINT     NOT NULL CHECK (ordre_passage >= 1),
    libelle         VARCHAR(120) NOT NULL,
    lat             NUMERIC(9,6) NOT NULL,
    lon             NUMERIC(9,6) NOT NULL,
    heure_passage   TIME         NOT NULL,
    UNIQUE (id_trajet, ordre_passage)
);

CREATE TABLE demande (
    id_demande            SERIAL PRIMARY KEY,
    id_demandeur          INTEGER      NOT NULL REFERENCES utilisateur,
    id_eleve              INTEGER,
    id_organisation       INTEGER      REFERENCES organisation,
    type_trajet           VARCHAR(12)  NOT NULL DEFAULT 'urbain'
        CHECK (type_trajet IN ('urbain', 'interurbain')),
    depart_libelle        VARCHAR(120) NOT NULL,
    depart_lat            NUMERIC(9,6) NOT NULL,
    depart_lon            NUMERIC(9,6) NOT NULL,
    arrivee_libelle       VARCHAR(120) NOT NULL,
    arrivee_lat           NUMERIC(9,6) NOT NULL,
    arrivee_lon           NUMERIC(9,6) NOT NULL,
    arrivee_au_plus_tot   TIME         NOT NULL,
    arrivee_au_plus_tard  TIME         NOT NULL,
    date_unique           DATE,
    jours_semaine         CHAR(7)      CHECK (jours_semaine ~ '^[01]{7}$' AND jours_semaine <> '0000000'),
    prix_max_fcfa         INTEGER      NOT NULL CHECK (prix_max_fcfa > 0),
    clim_obligatoire      BOOLEAN      NOT NULL DEFAULT FALSE,
    mode_reservation      VARCHAR(10)  NOT NULL DEFAULT 'manuel'
        CHECK (mode_reservation IN ('autonome', 'manuel')),
    cercle_max            VARCHAR(12)  NOT NULL DEFAULT 'partenaires'
        CHECK (cercle_max IN ('organisation', 'partenaires', 'public')),
    statut                VARCHAR(14)  NOT NULL DEFAULT 'ouverte'
        CHECK (statut IN ('ouverte', 'satisfaite', 'sans_equipage', 'annulee')),
    cree_le               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (arrivee_au_plus_tot < arrivee_au_plus_tard),
    CHECK ((date_unique IS NULL) <> (jours_semaine IS NULL)),
    -- un élève ne peut être inscrit à une demande que par son propre parent
    FOREIGN KEY (id_eleve, id_demandeur) REFERENCES compte_eleve (id_eleve, id_parent)
);

-- ---------------------------------------------------------------------
-- 5. Réservations, paiements, évaluations
-- ---------------------------------------------------------------------
CREATE TABLE reservation (
    id_reservation          SERIAL PRIMARY KEY,
    id_demande              INTEGER      NOT NULL REFERENCES demande,
    id_trajet               INTEGER      NOT NULL REFERENCES trajet,
    date_trajet             DATE         NOT NULL,
    heure_prise_en_charge   TIME         NOT NULL,
    heure_arrivee_estimee   TIME         NOT NULL,
    prix_fcfa               INTEGER      NOT NULL CHECK (prix_fcfa >= 0),
    detour_km               NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (detour_km >= 0),
    niveau_cercle           VARCHAR(12)  NOT NULL
        CHECK (niveau_cercle IN ('organisation', 'partenaires', 'public')),
    score                   NUMERIC(5,4) CHECK (score BETWEEN 0 AND 1),
    statut                  VARCHAR(10)  NOT NULL DEFAULT 'confirmee'
        CHECK (statut IN ('confirmee', 'annulee', 'terminee')),
    cree_le                 TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (heure_prise_en_charge < heure_arrivee_estimee)
);
-- Une demande n'a qu'une réservation confirmée par date (les annulées restent en historique).
CREATE UNIQUE INDEX ux_reservation_active
    ON reservation (id_demande, date_trajet) WHERE statut = 'confirmee';

CREATE TABLE paiement (
    id_paiement             SERIAL PRIMARY KEY,
    id_reservation          INTEGER     NOT NULL UNIQUE REFERENCES reservation,
    montant_fcfa            INTEGER     NOT NULL CHECK (montant_fcfa >= 0),
    commission_fcfa         INTEGER     NOT NULL DEFAULT 0 CHECK (commission_fcfa >= 0),
    moyen                   VARCHAR(14) NOT NULL DEFAULT 'mobile_money'
        CHECK (moyen IN ('mobile_money', 'especes')),
    operateur               VARCHAR(30),
    reference_transaction   VARCHAR(40) UNIQUE,
    statut                  VARCHAR(10) NOT NULL DEFAULT 'en_attente'
        CHECK (statut IN ('en_attente', 'reussi', 'echoue', 'rembourse')),
    paye_le                 TIMESTAMPTZ,
    CHECK (commission_fcfa <= montant_fcfa),
    CHECK (statut <> 'reussi' OR paye_le IS NOT NULL)
);

CREATE TABLE evaluation (
    id_evaluation       SERIAL PRIMARY KEY,
    id_reservation      INTEGER     NOT NULL REFERENCES reservation,
    id_auteur           INTEGER     NOT NULL REFERENCES utilisateur,
    id_evalue           INTEGER     NOT NULL REFERENCES utilisateur,
    note                SMALLINT    NOT NULL CHECK (note BETWEEN 1 AND 5),
    commentaire         VARCHAR(500),
    signalement_grave   BOOLEAN     NOT NULL DEFAULT FALSE,
    cree_le             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id_reservation, id_auteur),
    CHECK (id_auteur <> id_evalue)
);

-- ---------------------------------------------------------------------
-- 6. Index sur les clés étrangères et les recherches fréquentes
-- ---------------------------------------------------------------------
CREATE INDEX ix_appartenance_org    ON appartenance (id_organisation);
CREATE INDEX ix_vehicule_proprio    ON vehicule (id_proprietaire);
CREATE INDEX ix_eleve_parent        ON compte_eleve (id_parent);
CREATE INDEX ix_trajet_conducteur   ON trajet (id_conducteur);
CREATE INDEX ix_trajet_actifs       ON trajet (type_trajet, heure_depart) WHERE statut = 'actif';
CREATE INDEX ix_demande_demandeur   ON demande (id_demandeur);
CREATE INDEX ix_demande_ouvertes    ON demande (statut) WHERE statut = 'ouverte';
CREATE INDEX ix_reservation_trajet  ON reservation (id_trajet, date_trajet);
CREATE INDEX ix_evaluation_evalue   ON evaluation (id_evalue);

-- ---------------------------------------------------------------------
-- 7. Règles de gestion appliquées par déclencheurs
-- ---------------------------------------------------------------------

-- RG : seul un conducteur à l'agrément actif peut publier un trajet.
CREATE FUNCTION f_trajet_conducteur_agree() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM utilisateur
                   WHERE id_utilisateur = NEW.id_conducteur
                     AND est_conducteur AND statut_agrement = 'actif') THEN
        RAISE EXCEPTION 'Le conducteur % n''a pas d''agrément actif', NEW.id_conducteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER t_trajet_conducteur_agree
    BEFORE INSERT ON trajet FOR EACH ROW EXECUTE FUNCTION f_trajet_conducteur_agree();

-- RG : les places offertes ne dépassent pas celles du véhicule.
CREATE FUNCTION f_trajet_places() RETURNS trigger AS $$
BEGIN
    IF NEW.places_offertes > (SELECT places_passagers FROM vehicule WHERE id_vehicule = NEW.id_vehicule) THEN
        RAISE EXCEPTION 'Places offertes (%) supérieures à celles du véhicule', NEW.places_offertes;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER t_trajet_places
    BEFORE INSERT OR UPDATE OF places_offertes, id_vehicule ON trajet
    FOR EACH ROW EXECUTE FUNCTION f_trajet_places();

-- RG : un trajet ne reçoit pas plus de réservations confirmées que de places, pour une date donnée ;
--      un élève ne voyage que si son autorisation parentale est active.
CREATE FUNCTION f_reservation_controle() RETURNS trigger AS $$
DECLARE
    v_places  SMALLINT;
    v_prises  INTEGER;
    v_eleve   INTEGER;
BEGIN
    IF NEW.statut <> 'confirmee' THEN
        RETURN NEW;
    END IF;
    SELECT places_offertes INTO v_places FROM trajet WHERE id_trajet = NEW.id_trajet FOR UPDATE;
    SELECT count(*) INTO v_prises FROM reservation
     WHERE id_trajet = NEW.id_trajet AND date_trajet = NEW.date_trajet
       AND statut = 'confirmee' AND id_reservation <> NEW.id_reservation;
    IF v_prises >= v_places THEN
        RAISE EXCEPTION 'Trajet % complet le %', NEW.id_trajet, NEW.date_trajet;
    END IF;
    SELECT id_eleve INTO v_eleve FROM demande WHERE id_demande = NEW.id_demande;
    IF v_eleve IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM compte_eleve WHERE id_eleve = v_eleve AND autorisation_active) THEN
        RAISE EXCEPTION 'Autorisation parentale inactive pour l''élève %', v_eleve;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER t_reservation_controle
    BEFORE INSERT OR UPDATE OF statut, id_trajet, date_trajet ON reservation
    FOR EACH ROW EXECUTE FUNCTION f_reservation_controle();

-- RG : un signalement grave suspend immédiatement l'agrément du conducteur évalué.
CREATE FUNCTION f_signalement_suspend() RETURNS trigger AS $$
BEGIN
    IF NEW.signalement_grave THEN
        UPDATE utilisateur SET statut_agrement = 'suspendu'
         WHERE id_utilisateur = NEW.id_evalue AND est_conducteur;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER t_signalement_suspend
    AFTER INSERT ON evaluation FOR EACH ROW EXECUTE FUNCTION f_signalement_suspend();

-- ---------------------------------------------------------------------
-- 8. Vues pour l'application et la console des organisations
-- ---------------------------------------------------------------------
CREATE VIEW v_note_conducteur AS
SELECT u.id_utilisateur, u.prenom, u.nom,
       round(avg(e.note), 2) AS note_moyenne,
       count(e.*)            AS nb_evaluations,
       count(*) FILTER (WHERE e.signalement_grave) AS nb_signalements
  FROM utilisateur u
  LEFT JOIN evaluation e ON e.id_evalue = u.id_utilisateur
 WHERE u.est_conducteur
 GROUP BY u.id_utilisateur;

-- Tableau de bord d'une organisation : membres, trajets partagés, dépense des membres.
CREATE VIEW v_tableau_bord_organisation AS
SELECT o.id_organisation, o.nom,
       (SELECT count(*) FROM appartenance a WHERE a.id_organisation = o.id_organisation) AS membres,
       count(r.id_reservation) FILTER (WHERE r.statut IN ('confirmee', 'terminee')) AS trajets_partages,
       coalesce(sum(r.prix_fcfa) FILTER (WHERE r.statut = 'terminee'), 0)            AS depense_membres_fcfa,
       round(avg(r.detour_km), 2)                                                     AS detour_moyen_km
  FROM organisation o
  LEFT JOIN demande d     ON d.id_organisation = o.id_organisation
  LEFT JOIN reservation r ON r.id_demande = d.id_demande
 GROUP BY o.id_organisation;

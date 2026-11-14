-- =====================================================================
-- MboaRide · Migration des compléments du sprint 2 et du sprint 3
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- À exécuter après 04_sprint2.sql.
--   US13 : service ou département des membres et des invités
--   US13 : courriels envoyés (ou simulés) par la plateforme
--   US10 : paiement Mobile Money simulé (numéro payeur, tentatives, motif d'échec)
--   SR-47 : annulation d'un trajet pour une date, notifications aux passagers
-- =====================================================================
SET search_path TO mboaride;

-- ---------------------------------------------------------------------
-- US13 · Suivi de l'adoption par service
-- ---------------------------------------------------------------------
ALTER TABLE appartenance ADD COLUMN IF NOT EXISTS service VARCHAR(60);
ALTER TABLE invitation   ADD COLUMN IF NOT EXISTS service VARCHAR(60);

-- ---------------------------------------------------------------------
-- Courriels : chaque envoi est tracé, qu'il parte par SMTP ou soit simulé
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS courriel (
    id_courriel   SERIAL PRIMARY KEY,
    destinataire  VARCHAR(120) NOT NULL,
    sujet         VARCHAR(200) NOT NULL,
    corps         TEXT         NOT NULL,
    statut        VARCHAR(8)   NOT NULL CHECK (statut IN ('envoye', 'simule', 'echec')),
    erreur        VARCHAR(300),
    cree_le       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Notifications dans l'application (annulation, réaffectation, paiement)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification (
    id_notification SERIAL PRIMARY KEY,
    id_utilisateur  INTEGER      NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    type            VARCHAR(20)  NOT NULL
        CHECK (type IN ('annulation', 'reaffectation', 'offres', 'paiement', 'remboursement', 'invitation')),
    message         VARCHAR(400) NOT NULL,
    lue             BOOLEAN      NOT NULL DEFAULT FALSE,
    cree_le         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_notification_utilisateur ON notification (id_utilisateur, lue);

-- ---------------------------------------------------------------------
-- SR-47 · Un conducteur peut annuler une seule date de son trajet régulier
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS indisponibilite_trajet (
    id_trajet    INTEGER     NOT NULL REFERENCES trajet ON DELETE CASCADE,
    date_trajet  DATE        NOT NULL,
    motif        VARCHAR(200),
    cree_le      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id_trajet, date_trajet)
);

-- ---------------------------------------------------------------------
-- US10 · Paiement Mobile Money simulé
-- ---------------------------------------------------------------------
ALTER TABLE paiement
    ADD COLUMN IF NOT EXISTS telephone_payeur VARCHAR(20),
    ADD COLUMN IF NOT EXISTS initie_le        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS tentatives       SMALLINT NOT NULL DEFAULT 0 CHECK (tentatives BETWEEN 0 AND 3),
    ADD COLUMN IF NOT EXISTS motif_echec      VARCHAR(160),
    ADD COLUMN IF NOT EXISTS rembourse_le     TIMESTAMPTZ;

ALTER TABLE paiement DROP CONSTRAINT IF EXISTS ck_paiement_rembourse;
ALTER TABLE paiement ADD CONSTRAINT ck_paiement_rembourse
    CHECK (statut <> 'rembourse' OR rembourse_le IS NOT NULL);

-- ---------------------------------------------------------------------
-- Données de démonstration complémentaires
-- ---------------------------------------------------------------------
UPDATE appartenance SET service = 'Ressources humaines' WHERE id_utilisateur = 9 AND id_organisation = 1;
UPDATE appartenance SET service = 'Finance'             WHERE id_utilisateur = 2 AND id_organisation = 1;
UPDATE appartenance SET service = 'Technique'           WHERE id_utilisateur = 1 AND id_organisation = 1;

-- =====================================================================
-- MboaRide · Console d'administration, deuxième partie
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- À exécuter après 11_administration.sql. Le script peut être rejoué.
--
--   Paramètres : tarifs et délais réglables depuis la console, lus par l'API Python
--     (prix, validation des fins de course, agréments) et par l'API Node (code OTP).
--   Signalements : chaque évaluation signalée est traitée par l'équipe (classée,
--     avertissement, suspension), avec une note.
--   Annonces : messages envoyés par l'équipe à un groupe d'utilisateurs.
-- =====================================================================
SET search_path TO mboaride;

CREATE TABLE IF NOT EXISTS parametre (
    cle      VARCHAR(40) PRIMARY KEY,
    valeur   INTEGER     NOT NULL,
    maj_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
    maj_par  INTEGER     REFERENCES utilisateur ON DELETE SET NULL
);
INSERT INTO parametre (cle, valeur) VALUES
    ('prix_carburant_fcfa_l', 840),
    ('commission_pct', 10),
    ('arrondi_fcfa', 25),
    ('prix_minimum_fcfa', 100),
    ('validation_auto_heures', 24),
    ('agrement_validite_mois', 12),
    ('otp_minutes', 5)
ON CONFLICT (cle) DO NOTHING;

ALTER TABLE evaluation
    ADD COLUMN IF NOT EXISTS traite_le        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS traite_par       INTEGER REFERENCES utilisateur ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS decision         VARCHAR(20),
    ADD COLUMN IF NOT EXISTS note_traitement  VARCHAR(300);
ALTER TABLE evaluation DROP CONSTRAINT IF EXISTS ck_evaluation_decision;
ALTER TABLE evaluation ADD CONSTRAINT ck_evaluation_decision
    CHECK (decision IS NULL OR decision IN ('classe', 'avertissement', 'suspension_agrement', 'suspension_compte'));
CREATE INDEX IF NOT EXISTS ix_evaluation_a_traiter ON evaluation (cree_le) WHERE signalement_grave AND traite_le IS NULL;

CREATE TABLE IF NOT EXISTS annonce (
    id_annonce       SERIAL       PRIMARY KEY,
    cible            VARCHAR(14)  NOT NULL
        CHECK (cible IN ('tous', 'conducteurs', 'passagers', 'organisation', 'utilisateur')),
    id_organisation  INTEGER      REFERENCES organisation ON DELETE SET NULL,
    id_utilisateur   INTEGER      REFERENCES utilisateur ON DELETE SET NULL,
    message          VARCHAR(400) NOT NULL,
    par_email        BOOLEAN      NOT NULL DEFAULT FALSE,
    destinataires    INTEGER      NOT NULL DEFAULT 0,
    courriels        INTEGER      NOT NULL DEFAULT 0,
    envoye_par       INTEGER      REFERENCES utilisateur ON DELETE SET NULL,
    cree_le          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

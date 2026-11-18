-- =====================================================================
-- MboaRide · Console d'administration de la plateforme
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- À exécuter après 10_portefeuille_fin_de_course.sql. Le script peut être rejoué.
--
--   Administrateurs : l'équipe MboaRide, distincte des administrateurs d'une
--     organisation (table appartenance). Trois rôles :
--       super_admin : tout, y compris nommer d'autres administrateurs ;
--       support     : utilisateurs, agréments, trajets ;
--       finance     : paiements, remboursements, versements, commissions.
--   Journal : chaque action d'un administrateur est tracée.
--   Suspension : un compte suspendu ne peut plus utiliser l'application.
--   Agrément : qui a vérifié chaque pièce, quand, et pourquoi elle a été refusée.
-- =====================================================================
SET search_path TO mboaride;

CREATE TABLE IF NOT EXISTS administrateur (
    id_utilisateur  INTEGER      PRIMARY KEY REFERENCES utilisateur ON DELETE CASCADE,
    role            VARCHAR(12)  NOT NULL DEFAULT 'support'
        CHECK (role IN ('super_admin', 'support', 'finance')),
    actif           BOOLEAN      NOT NULL DEFAULT TRUE,
    cree_le         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    cree_par        INTEGER      REFERENCES utilisateur ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS journal_admin (
    id_entree    SERIAL       PRIMARY KEY,
    id_admin     INTEGER      REFERENCES utilisateur ON DELETE SET NULL,
    action       VARCHAR(40)  NOT NULL,
    cible_type   VARCHAR(20)  NOT NULL,
    cible_id     VARCHAR(40),
    resume       VARCHAR(300) NOT NULL,
    details      JSONB        NOT NULL DEFAULT '{}'::jsonb,
    cree_le      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_journal_admin_date  ON journal_admin (cree_le DESC);
CREATE INDEX IF NOT EXISTS ix_journal_admin_cible ON journal_admin (cible_type, cible_id);

-- Suspension d'un compte par l'équipe MboaRide.
ALTER TABLE utilisateur
    ADD COLUMN IF NOT EXISTS suspendu_le       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS motif_suspension  VARCHAR(300);

-- Vérification des pièces d'agrément.
ALTER TABLE document_agrement
    ADD COLUMN IF NOT EXISTS motif_refus  VARCHAR(300),
    ADD COLUMN IF NOT EXISTS verifie_par  INTEGER REFERENCES utilisateur ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verifie_le   TIMESTAMPTZ;

-- Message de l'équipe MboaRide à un utilisateur (pièce refusée, compte suspendu...).
ALTER TABLE notification DROP CONSTRAINT IF EXISTS notification_type_check;
ALTER TABLE notification ADD CONSTRAINT notification_type_check
    CHECK (type IN ('annulation', 'reaffectation', 'offres', 'paiement', 'remboursement',
                    'invitation', 'depart', 'arrivee', 'retard',
                    'course', 'fin_course', 'versement', 'portefeuille', 'administration'));

-- Recherches fréquentes de la console.
CREATE INDEX IF NOT EXISTS ix_utilisateur_cree_le  ON utilisateur (cree_le DESC);
CREATE INDEX IF NOT EXISTS ix_paiement_statut      ON paiement (statut);
CREATE INDEX IF NOT EXISTS ix_document_statut      ON document_agrement (statut);

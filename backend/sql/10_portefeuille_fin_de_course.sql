-- =====================================================================
-- MboaRide · Portefeuille, fin de course, point de ramassage
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- À exécuter après 09_comptes_mobile_money.sql. Le script peut être rejoué.
--
--   Ramassage : le conducteur décrit où et comment il prend ses passagers.
--   Portefeuille : chaque utilisateur a un solde en FCFA, alimenté par Mobile Money
--     (recharge), par ses gains de conducteur et par les remboursements ; il paie ses
--     trajets avec et peut le vider vers son compte Mobile Money (retrait).
--   Fin de course : le paiement du passager reste chez MboaRide (séquestre) jusqu'à ce
--     que chaque passager de l'équipage valide la fin de la course ; le conducteur
--     reçoit alors le prix moins la commission de 10 %, qui revient à MboaRide.
-- =====================================================================
SET search_path TO mboaride;

-- ---------------------------------------------------------------------
-- Point de ramassage indiqué par le conducteur à la publication
-- ---------------------------------------------------------------------
ALTER TABLE trajet
    ADD COLUMN IF NOT EXISTS point_ramassage     VARCHAR(160),
    ADD COLUMN IF NOT EXISTS consignes_ramassage VARCHAR(300),
    ADD COLUMN IF NOT EXISTS attente_max_min     SMALLINT NOT NULL DEFAULT 5
        CHECK (attente_max_min BETWEEN 0 AND 30);

-- ---------------------------------------------------------------------
-- Paiement : par le portefeuille, puis versement au conducteur
-- ---------------------------------------------------------------------
ALTER TABLE paiement DROP CONSTRAINT IF EXISTS paiement_moyen_check;
ALTER TABLE paiement ADD CONSTRAINT paiement_moyen_check
    CHECK (moyen IN ('mobile_money', 'especes', 'portefeuille'));
ALTER TABLE paiement
    ADD COLUMN IF NOT EXISTS verse_le           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS montant_verse_fcfa INTEGER CHECK (montant_verse_fcfa IS NULL OR montant_verse_fcfa >= 0);
ALTER TABLE paiement DROP CONSTRAINT IF EXISTS ck_paiement_verse;
ALTER TABLE paiement ADD CONSTRAINT ck_paiement_verse
    CHECK (verse_le IS NULL OR (statut = 'reussi' AND montant_verse_fcfa IS NOT NULL));

-- ---------------------------------------------------------------------
-- Fin de course
-- ---------------------------------------------------------------------
ALTER TABLE reservation ADD COLUMN IF NOT EXISTS fin_validee_le TIMESTAMPTZ;

-- Une course : un trajet un jour donné, démarré par le conducteur.
CREATE TABLE IF NOT EXISTS course (
    id_trajet    INTEGER     NOT NULL REFERENCES trajet ON DELETE CASCADE,
    date_trajet  DATE        NOT NULL,
    statut       VARCHAR(10) NOT NULL DEFAULT 'en_cours'
        CHECK (statut IN ('en_cours', 'arrivee', 'reglee')),
    demarree_le  TIMESTAMPTZ NOT NULL DEFAULT now(),
    arrivee_le   TIMESTAMPTZ,
    reglee_le    TIMESTAMPTZ,
    PRIMARY KEY (id_trajet, date_trajet),
    CHECK (statut <> 'reglee' OR reglee_le IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- Portefeuille
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS portefeuille (
    id_utilisateur  INTEGER     PRIMARY KEY REFERENCES utilisateur ON DELETE CASCADE,
    solde_fcfa      INTEGER     NOT NULL DEFAULT 0 CHECK (solde_fcfa >= 0),
    -- Gains virés aussitôt vers le compte Mobile Money par défaut.
    virement_auto   BOOLEAN     NOT NULL DEFAULT FALSE,
    maj_le          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mouvement_portefeuille (
    id_mouvement      SERIAL       PRIMARY KEY,
    id_utilisateur    INTEGER      NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    type              VARCHAR(14)  NOT NULL
        CHECK (type IN ('recharge', 'paiement', 'remboursement', 'gain', 'retrait')),
    montant_fcfa      INTEGER      NOT NULL CHECK (montant_fcfa <> 0),
    solde_apres_fcfa  INTEGER      NOT NULL CHECK (solde_apres_fcfa >= 0),
    libelle           VARCHAR(200) NOT NULL,
    reference         VARCHAR(40),
    id_reservation    INTEGER      REFERENCES reservation ON DELETE SET NULL,
    cree_le           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK ((type IN ('recharge', 'remboursement', 'gain')) = (montant_fcfa > 0))
);
CREATE INDEX IF NOT EXISTS ix_mouvement_utilisateur ON mouvement_portefeuille (id_utilisateur, cree_le DESC);

-- Commission de 10 % gardée par MboaRide, au versement de chaque course.
CREATE TABLE IF NOT EXISTS commission_mboaride (
    id_paiement   INTEGER     PRIMARY KEY REFERENCES paiement,
    montant_fcfa  INTEGER     NOT NULL CHECK (montant_fcfa >= 0),
    preleve_le    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Notifications : course démarrée ou arrivée, fin validée, versement, portefeuille
-- ---------------------------------------------------------------------
ALTER TABLE notification DROP CONSTRAINT IF EXISTS notification_type_check;
ALTER TABLE notification ADD CONSTRAINT notification_type_check
    CHECK (type IN ('annulation', 'reaffectation', 'offres', 'paiement', 'remboursement',
                    'invitation', 'depart', 'arrivee', 'retard',
                    'course', 'fin_course', 'versement', 'portefeuille', 'administration'));

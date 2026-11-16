-- =====================================================================
-- MboaRide · Migration du sprint 2 (cœur et interface)
-- Groupe 8 · NGUIMBI Valerdy, MOUKAM Cindy, DJEGUE Wilfried, NGAPEPOUE Karl
--
-- À exécuter après 01_schema.sql (et 02_donnees_exemple.sql pour la démo).
--   US02 : prix maximal par défaut dans les préférences
--   US13 : effectif déclaré de l'organisation, invitations nominatives
--   US14 : vue des trajets partagés utilisée pour les économies et le CO2
-- =====================================================================
SET search_path TO mboaride;

-- ---------------------------------------------------------------------
-- US02 · Préférences : prix maximal proposé par défaut à chaque demande
-- (confort souhaité, cercle, mode et priorité existent déjà dans utilisateur)
-- ---------------------------------------------------------------------
ALTER TABLE utilisateur
    ADD COLUMN IF NOT EXISTS prix_max_defaut_fcfa INTEGER NOT NULL DEFAULT 500
        CHECK (prix_max_defaut_fcfa BETWEEN 50 AND 20000),
    ADD COLUMN IF NOT EXISTS preferences_maj_le TIMESTAMPTZ;

-- Le réseau public n'a de sens que si les partenaires sont aussi acceptés :
-- les cercles sont emboîtés (collègues ⊂ partenaires ⊂ public).
ALTER TABLE utilisateur
    ADD CONSTRAINT ck_cercles_emboites CHECK (NOT accepte_public OR accepte_partenaires);

-- ---------------------------------------------------------------------
-- US13 · Effectif de l'organisation (dénominateur du taux d'adoption)
-- ---------------------------------------------------------------------
ALTER TABLE organisation
    ADD COLUMN IF NOT EXISTS effectif INTEGER CHECK (effectif IS NULL OR effectif > 0),
    ADD COLUMN IF NOT EXISTS objectif_adoption NUMERIC(3,2) NOT NULL DEFAULT 0.30
        CHECK (objectif_adoption > 0 AND objectif_adoption <= 1);

-- ---------------------------------------------------------------------
-- US13 · Invitations nominatives envoyées par l'administrateur
-- Une invitation par adresse et par organisation ; le lien porte un jeton unique.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invitation (
    id_invitation    SERIAL PRIMARY KEY,
    id_organisation  INTEGER      NOT NULL REFERENCES organisation ON DELETE CASCADE,
    email            VARCHAR(120) NOT NULL,
    jeton            CHAR(32)     NOT NULL UNIQUE,
    id_invite_par    INTEGER      NOT NULL REFERENCES utilisateur,
    id_utilisateur   INTEGER      REFERENCES utilisateur,          -- renseigné à l'acceptation
    statut           VARCHAR(10)  NOT NULL DEFAULT 'envoyee'
        CHECK (statut IN ('envoyee', 'acceptee', 'expiree', 'annulee')),
    envoyee_le       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    acceptee_le      TIMESTAMPTZ,
    expire_le        TIMESTAMPTZ  NOT NULL DEFAULT now() + INTERVAL '30 days',
    relances         SMALLINT     NOT NULL DEFAULT 0 CHECK (relances BETWEEN 0 AND 3),
    UNIQUE (id_organisation, email),
    CHECK (email = lower(email) AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CHECK ((statut = 'acceptee') = (acceptee_le IS NOT NULL AND id_utilisateur IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_invitation_org ON invitation (id_organisation, statut);

-- ---------------------------------------------------------------------
-- US14 · Trajets partagés effectués ou confirmés, avec leur organisation
-- et les coordonnées nécessaires au calcul des km évités.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_trajet_partage AS
SELECT r.id_reservation, r.date_trajet, r.statut, r.prix_fcfa, r.detour_km, r.niveau_cercle,
       d.id_demande, d.id_demandeur, d.id_eleve, d.id_organisation, d.type_trajet,
       d.depart_lat, d.depart_lon, d.arrivee_lat, d.arrivee_lon,
       t.id_conducteur
  FROM reservation r
  JOIN demande d ON d.id_demande = r.id_demande
  JOIN trajet  t ON t.id_trajet  = r.id_trajet
 WHERE r.statut IN ('confirmee', 'terminee');

-- ---------------------------------------------------------------------
-- Données de démonstration complémentaires (sans effet si 02 n'a pas été chargé)
-- ---------------------------------------------------------------------
UPDATE organisation SET effectif = 250 WHERE code_invitation = 'ENTA-2026';
UPDATE organisation SET effectif = 120 WHERE code_invitation = 'ENTB-2026';
UPDATE utilisateur  SET prix_max_defaut_fcfa = 400 WHERE telephone = '+237600000002';

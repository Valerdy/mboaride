-- ---------------------------------------------------------------------
-- Comptes Mobile Money enregistrés par les passagers (US10)
-- ---------------------------------------------------------------------
-- Le passager enregistre une fois son opérateur, son numéro et le nom du titulaire ;
-- il paie ensuite ses trajets en choisissant ce compte. Aucun code secret n'est stocké :
-- il ne se saisit que sur le téléphone, au moment de valider le paiement.

SET search_path TO mboaride;

CREATE TABLE IF NOT EXISTS compte_mobile_money (
    id_compte       SERIAL       PRIMARY KEY,
    id_utilisateur  INTEGER      NOT NULL REFERENCES utilisateur ON DELETE CASCADE,
    operateur       VARCHAR(10)  NOT NULL CHECK (operateur IN ('mtn', 'orange')),
    telephone       VARCHAR(20)  NOT NULL,
    titulaire       VARCHAR(80)  NOT NULL,
    par_defaut      BOOLEAN      NOT NULL DEFAULT FALSE,
    cree_le         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (id_utilisateur, telephone)
);
CREATE INDEX IF NOT EXISTS ix_compte_mm_utilisateur ON compte_mobile_money (id_utilisateur);

COMMENT ON TABLE compte_mobile_money IS
    'Comptes Mobile Money du passager (opérateur, numéro, titulaire), sans code secret.';

-- ---------------------------------------------------------------------
-- Parcours complet dans l'application : règles du conducteur
-- ---------------------------------------------------------------------
-- L'écran « Cercles et règles » du conducteur règle, en plus des partenaires et du public
-- (déjà dans utilisateur), les collègues, les élèves et un prix minimal par passager.
-- Les trois sont appliqués à l'évaluation d'une offre (routes/prix.py) ; le prix minimal
-- est le plancher `min_price` de l'agent conducteur (mboaride_agents.pricing.quote).
-- Valeurs par défaut choisies pour ne rien changer aux données existantes.

SET search_path TO mboaride;

ALTER TABLE utilisateur
    ADD COLUMN IF NOT EXISTS accepte_collegues BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS accepte_eleves    BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS prix_min_fcfa     INTEGER NOT NULL DEFAULT 0
        CHECK (prix_min_fcfa BETWEEN 0 AND 20000);

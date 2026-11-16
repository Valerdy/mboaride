-- ---------------------------------------------------------------------
-- US17 et US19 · Comptes élèves et notifications aux parents
-- ---------------------------------------------------------------------
-- Les notifications du parent portent sur un élève et, le plus souvent, sur une
-- réservation précise : on les rattache pour pouvoir afficher le journal d'un élève.

ALTER TABLE notification DROP CONSTRAINT IF EXISTS notification_type_check;
ALTER TABLE notification ADD CONSTRAINT notification_type_check
    CHECK (type IN ('annulation', 'reaffectation', 'offres', 'paiement', 'remboursement',
                    'invitation', 'depart', 'arrivee', 'retard'));

ALTER TABLE notification ADD COLUMN IF NOT EXISTS id_eleve INTEGER
    REFERENCES compte_eleve ON DELETE CASCADE;
ALTER TABLE notification ADD COLUMN IF NOT EXISTS id_reservation INTEGER
    REFERENCES reservation;

CREATE INDEX IF NOT EXISTS ix_notification_eleve ON notification (id_eleve, cree_le DESC);

-- Plusieurs places dans une même réservation.
-- Un passager peut demander 1 à 8 places (lui et ses proches) ; elles sont réservées ensemble, payées
-- ensemble, au même prix par place que les autres passagers de l'équipage.

ALTER TABLE demande
    ADD COLUMN IF NOT EXISTS nb_places SMALLINT NOT NULL DEFAULT 1 CHECK (nb_places BETWEEN 1 AND 8);
ALTER TABLE reservation
    ADD COLUMN IF NOT EXISTS nb_places SMALLINT NOT NULL DEFAULT 1 CHECK (nb_places BETWEEN 1 AND 8);

-- RG : un trajet ne reçoit pas plus de places confirmées que de places offertes, pour une date donnée.
CREATE OR REPLACE FUNCTION f_reservation_controle() RETURNS trigger AS $$
DECLARE
    v_places  SMALLINT;
    v_prises  INTEGER;
    v_eleve   INTEGER;
BEGIN
    IF NEW.statut <> 'confirmee' THEN
        RETURN NEW;
    END IF;
    SELECT places_offertes INTO v_places FROM trajet WHERE id_trajet = NEW.id_trajet FOR UPDATE;
    SELECT coalesce(sum(nb_places), 0) INTO v_prises FROM reservation
     WHERE id_trajet = NEW.id_trajet AND date_trajet = NEW.date_trajet
       AND statut = 'confirmee' AND id_reservation <> NEW.id_reservation;
    IF v_prises + NEW.nb_places > v_places THEN
        IF v_prises >= v_places THEN
            RAISE EXCEPTION 'Trajet % complet le %', NEW.id_trajet, NEW.date_trajet;
        END IF;
        RAISE EXCEPTION 'Trajet % : il ne reste que % place(s) le %', NEW.id_trajet, v_places - v_prises, NEW.date_trajet;
    END IF;
    SELECT id_eleve INTO v_eleve FROM demande WHERE id_demande = NEW.id_demande;
    IF v_eleve IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM compte_eleve WHERE id_eleve = v_eleve AND autorisation_active) THEN
        RAISE EXCEPTION 'Autorisation parentale inactive pour l''élève %', v_eleve;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- Le déclencheur écoute aussi le nombre de places.
DROP TRIGGER IF EXISTS t_reservation_controle ON reservation;
CREATE TRIGGER t_reservation_controle
    BEFORE INSERT OR UPDATE OF statut, id_trajet, date_trajet, nb_places ON reservation
    FOR EACH ROW EXECUTE FUNCTION f_reservation_controle();

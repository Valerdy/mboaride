"""Données de démonstration du sprint 2 : deux mois et demi d'activité fictive pour
« Entreprise A (Bonanjo) », afin que la console (US13, US14) montre des chiffres réalistes.

    python -m scripts.seed_demo            (après les scripts de sql/ ; idempotent : rejouable)

Personnes, numéros et adresses sont inventés. Les prix et horaires sont calculés avec
les règles des agents (agents/mboaride_agents), comme dans l'application.
"""

from __future__ import annotations

import random
from datetime import date, timedelta

from app import moteur
from app.db import connect

# Centres approximatifs des quartiers de Douala (latitude, longitude).
QUARTIERS = {
    "Bonanjo": (4.0420, 9.6890), "Deido": (4.0630, 9.7050), "Bépanda": (4.0610, 9.7230),
    "Ndokoti": (4.0440, 9.7370), "Cité des Palmiers": (4.0700, 9.7420), "Ndogbong": (4.0570, 9.7480),
    "Makepe": (4.0810, 9.7520), "Bonamoussadi": (4.0960, 9.7420), "Kotto": (4.0720, 9.7660),
    "Logpom": (4.0880, 9.7650), "Bassa": (4.0290, 9.7580), "Village": (4.0320, 9.7440),
}

ORG = 1                       # Entreprise A (Bonanjo)
DEBUT, FIN = date(2026, 9, 1), date(2026, 11, 11)
DEST = ("Bonanjo", *QUARTIERS["Bonanjo"])
PRENOMS = ["Aïcha", "Bertrand", "Carine", "Didier", "Estelle", "Franck", "Gisèle", "Hervé",
           "Inès", "Jules", "Karine", "Landry", "Murielle", "Nestor", "Olive", "Patrick",
           "Rachel", "Samuel", "Thérèse", "Ulrich", "Vanessa", "Wilfried", "Yvette", "Zacharie",
           "Alain", "Brigitte", "Cédric", "Danielle", "Emmanuel", "Flore", "Georges", "Hortense",
           "Ivan", "Josiane", "Kevin", "Lucie", "Marcel", "Nicole", "Oscar", "Pauline", "Roger",
           "Sandrine"]
QUARTIERS_RES = ["Logpom", "Kotto", "Makepe", "Bonamoussadi", "Cité des Palmiers", "Ndogbong",
                 "Bépanda", "Deido", "Bassa", "Village", "Ndokoti"]


def jitter(rng, q):
    lat, lon = QUARTIERS[q]
    return round(lat + rng.uniform(-0.004, 0.004), 6), round(lon + rng.uniform(-0.004, 0.004), 6)


def depart_pour_arriver(lat, lon, rng) -> str:
    """Heure de départ pour arriver vers 07:35-07:45 à Bonanjo, détour compris."""
    km = moteur.distance_km(lat, lon, *QUARTIERS["Bonanjo"]) + 2.0
    m = 7 * 60 + rng.choice([35, 40, 45]) - km / 20.0 * 60     # 20 km/h aux heures de pointe
    m = int(m // 5 * 5)
    return f"{m // 60:02d}:{m % 60:02d}"


def jours_ouvres(a: date, b: date):
    d = a
    while d <= b:
        if d.weekday() < 5:
            yield d
        d += timedelta(days=1)


SERVICES = ["Finance", "Commercial", "Commercial", "Technique", "Technique", "Logistique", "Ressources humaines"]


def main() -> None:
    rng = random.Random(2026)
    conn = connect()
    with conn.transaction():
        demo = "SELECT id_utilisateur FROM utilisateur WHERE telephone LIKE '+2376999%'"
        conn.execute("DELETE FROM invitation WHERE id_organisation = %s", (ORG,))
        conn.execute("DELETE FROM courriel")
        conn.execute(f"""DELETE FROM paiement WHERE id_reservation IN (
                           SELECT r.id_reservation FROM reservation r JOIN demande d USING (id_demande)
                            JOIN trajet t USING (id_trajet)
                           WHERE d.id_demandeur IN ({demo}) OR t.id_conducteur IN ({demo}))""")
        conn.execute(f"""DELETE FROM reservation WHERE id_demande IN (SELECT id_demande FROM demande
                           WHERE id_demandeur IN ({demo}))
                           OR id_trajet IN (SELECT id_trajet FROM trajet WHERE id_conducteur IN ({demo}))""")
        conn.execute(f"DELETE FROM demande WHERE id_demandeur IN ({demo})")
        conn.execute(f"DELETE FROM trajet WHERE id_conducteur IN ({demo})")
        conn.execute(f"DELETE FROM utilisateur WHERE id_utilisateur IN ({demo})")

        def creer(prenom, nom, conducteur, adhesion):
            n = conn.execute("SELECT count(*) n FROM utilisateur WHERE telephone LIKE '+2376999%'").fetchone()["n"]
            u = conn.execute(
                """INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache,
                       est_conducteur, statut_agrement, date_agrement, accepte_partenaires,
                       consentement_position, souhaite_clim, prix_max_defaut_fcfa, cree_le)
                   VALUES (%s, %s, %s, %s, '$2b$12$demo', %s, %s, %s, TRUE, TRUE, %s, 500, %s)
                   RETURNING id_utilisateur""",
                (nom, prenom, f"+2376999{n:05d}", f"{prenom.lower()}.{nom.lower()}@entreprise-a.cm"
                 .replace("ï", "i").replace("è", "e").replace("é", "e"),
                 conducteur, "actif" if conducteur else "non_demande",
                 adhesion if conducteur else None, rng.random() < 0.5, adhesion)).fetchone()["id_utilisateur"]
            conn.execute("INSERT INTO appartenance (id_utilisateur, id_organisation, date_adhesion, service) "
                         "VALUES (%s, %s, %s, %s)", (u, ORG, adhesion, rng.choice(SERVICES)))
            return u

        def adhesion_aleatoire():
            # forte vague au lancement (septembre), puis adoption plus lente
            jours = (FIN - DEBUT).days
            return DEBUT + timedelta(days=int(jours * rng.random() ** 1.6))

        noms = iter(PRENOMS)
        # Conducteurs : 10 collègues agréés, une voiture de 3 places chacun.
        conducteurs = []
        for i in range(10):
            q = QUARTIERS_RES[i % len(QUARTIERS_RES)]
            adh = DEBUT + timedelta(days=rng.randint(0, 12))
            u = creer(next(noms), "Conducteur", True, adh)
            v = conn.execute(
                """INSERT INTO vehicule (id_proprietaire, marque_modele, immatriculation, places_passagers,
                       conso_l_100km, climatise) VALUES (%s, 'Berline', %s, 3, %s, %s)
                   RETURNING id_vehicule""",
                (u, f"LT-9{i:02d}-DM", rng.choice([6.5, 7.0, 7.5, 8.0, 8.5]), rng.random() < 0.6)
            ).fetchone()["id_vehicule"]
            lat, lon = jitter(rng, q)
            t = conn.execute(
                """INSERT INTO trajet (id_conducteur, id_vehicule, depart_libelle, depart_lat, depart_lon,
                       arrivee_libelle, arrivee_lat, arrivee_lon, heure_depart, jours_semaine,
                       places_offertes, detour_max_km)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, '1111100', 3, 4.0) RETURNING *""",
                (u, v, q, lat, lon, *DEST, depart_pour_arriver(lat, lon, rng))).fetchone()
            t.update(conn.execute("SELECT conso_l_100km, climatise, non_fumeur FROM vehicule "
                                  "WHERE id_vehicule = %s", (v,)).fetchone())
            conducteurs.append({"trajet": t, "places": 3, "id": u, "adh": adh})

        # Passagers : 32 collègues, chacun avec une demande régulière vers Bonanjo.
        passagers = []
        for i in range(32):
            q = rng.choice(QUARTIERS_RES[:10])
            adh = adhesion_aleatoire()
            u = creer(next(noms), "Passager", False, adh)
            lat, lon = jitter(rng, q)
            d = conn.execute(
                """INSERT INTO demande (id_demandeur, id_organisation, depart_libelle, depart_lat, depart_lon,
                       arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot, arrivee_au_plus_tard,
                       jours_semaine, prix_max_fcfa, cercle_max, statut, cree_le)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, '07:20', '08:00', '1111100', 500,
                           'organisation', 'ouverte', %s) RETURNING *""",
                (u, ORG, q, lat, lon, *DEST, adh)).fetchone()
            passagers.append((u, adh, d))

        # Affectation : le conducteur libre au plus petit détour, horaires compatibles.
        for u, adh, d in sorted(passagers, key=lambda p: p[1]):
            req = moteur.request_from_row(d)
            options = []
            for c in conducteurs:
                if c["places"] == 0:
                    continue
                drv = moteur.driver_from_row(c["trajet"])
                h = moteur.horaires(drv, req)
                if h:
                    options.append((h[2], c["id"], c, drv, h))
            if not options:
                continue
            _, _, c, drv, h = min(options, key=lambda o: (o[0], o[1]))
            c["places"] -= 1
            prix = moteur.detail_prix(drv, req, 0).prix_fcfa
            debut = max(adh, c["adh"], date(2026, 9, 7))
            for jour in jours_ouvres(debut, FIN):
                if rng.random() < 0.82:       # absences, congés, télétravail
                    conn.execute(
                        """INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge,
                               heure_arrivee_estimee, prix_fcfa, detour_km, niveau_cercle, statut)
                           VALUES (%s, %s, %s, %s, %s, %s, %s, 'organisation', 'terminee')""",
                        (d["id_demande"], c["trajet"]["id_trajet"], jour, h[0], h[1], prix, h[2]))
            conn.execute("UPDATE demande SET statut = 'satisfaite' WHERE id_demande = %s", (d["id_demande"],))

        # Demande ouverte de Grâce pour la démo du prix (US09).
        conn.execute("DELETE FROM demande d WHERE id_demandeur = 2 AND statut = 'ouverte' "
                     "AND NOT EXISTS (SELECT 1 FROM reservation r WHERE r.id_demande = d.id_demande)")
        conn.execute(
            """INSERT INTO demande (id_demandeur, id_organisation, depart_libelle, depart_lat, depart_lon,
                   arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot, arrivee_au_plus_tard,
                   date_unique, prix_max_fcfa, cercle_max, statut)
               VALUES (2, 1, 'Makepe', 4.081000, 9.752000, 'Bonanjo', 4.042000, 9.689000,
                       '07:20', '08:00', '2026-11-16', 400, 'partenaires', 'ouverte')""")

        # Invitations : acceptées pour les membres arrivés par lien, en attente ou expirées sinon.
        membres = conn.execute(
            """SELECT u.id_utilisateur, u.email, a.date_adhesion FROM utilisateur u
                 JOIN appartenance a USING (id_utilisateur)
                WHERE a.id_organisation = %s AND u.telephone LIKE '+2376999%%'""", (ORG,)).fetchall()
        for m in membres:
            env = m["date_adhesion"] - timedelta(days=rng.randint(1, 6))
            conn.execute(
                """INSERT INTO invitation (id_organisation, email, jeton, id_invite_par, id_utilisateur,
                       statut, envoyee_le, acceptee_le, expire_le, service)
                   VALUES (%s, %s, md5(%s), 9, %s, 'acceptee', %s, %s, %s,
                           (SELECT service FROM appartenance WHERE id_utilisateur = %s AND id_organisation = %s))""",
                (ORG, m["email"], m["email"], m["id_utilisateur"], env, m["date_adhesion"],
                 env + timedelta(days=30), m["id_utilisateur"], ORG))
        for i, prenom in enumerate(PRENOMS[:26]):
            email = f"{prenom.lower()}.invite{i}@entreprise-a.cm".replace("ï", "i").replace("è", "e").replace("é", "e")
            env = date(2026, 9, 3) + timedelta(days=rng.randint(0, 68))
            conn.execute(
                """INSERT INTO invitation (id_organisation, email, jeton, id_invite_par, statut, envoyee_le,
                       expire_le, relances, service)
                   VALUES (%s, %s, md5(%s), 9, 'envoyee', %s, %s, %s, %s)""",
                (ORG, email, email, env, env + timedelta(days=30), rng.randint(0, 2), rng.choice(SERVICES)))
    conn.commit()
    n = conn.execute("SELECT count(*) n FROM reservation").fetchone()["n"]
    print(f"Démo chargée : {len(conducteurs)} conducteurs, {len(passagers)} passagers, {n} réservations")
    conn.close()


if __name__ == "__main__":
    main()

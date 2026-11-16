"""Console des organisations.

US13 · Inviter les employés et suivre l'adoption (partiel)
  1. L'administrateur colle une liste d'adresses ; chaque adresse valide reçoit une
     invitation nominative avec un lien unique, valable 30 jours.
  2. Les adresses invalides, hors du domaine de l'organisation, déjà membres ou déjà
     invitées sont écartées avec leur motif, sans bloquer les autres.
  3. L'administrateur suit chaque invitation (envoyée, acceptée, expirée) et peut relancer
     trois fois au plus.
  4. En suivant le lien, l'invité rejoint le cercle de l'organisation.
  5. Le tableau d'adoption affiche membres, taux d'adoption sur l'effectif, objectif,
     membres actifs sur 30 jours et l'évolution mois par mois.
  6. Chaque invitation part par e-mail (SMTP si configuré, sinon envoi simulé et tracé) ;
     le lien reste affiché pour être transmis aussi par SMS ou messagerie.
  7. Une adresse peut porter un service (« adresse ; Service ») ; l'adoption est suivie
     par service.
  8. Un invité sans compte crée le sien directement depuis le lien, avec l'adresse invitée.

US14 · Voir les économies et le CO2 évité
  1. Sur une période choisie, la console affiche les trajets partagés des membres, les km
     de voiture évités, les litres et le CO2 évités (fourchette prudente et haute), les
     économies des employés par rapport au taxi ou au car et le coût de l'abonnement.
  2. Les calculs reprennent les hypothèses du bilan développement durable, affichées
     avec les résultats.
  3. L'évolution est donnée mois par mois.
  4. Le bilan de la période s'exporte en CSV (ouvrable dans Excel) pour un rapport RSE.
"""

from __future__ import annotations

import csv
import hashlib
import io
import re
import secrets
from datetime import date, timedelta

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field

from .. import config, moteur
from ..notifications import URL_PUBLIQUE, envoyer_courriel, smtp_actif
from ..db import get_conn
from ..securite import exiger_admin, utilisateur_courant

router = APIRouter(prefix="/api", tags=["US13 · Invitations et adoption", "US14 · Économies et CO2"])

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


TELEPHONE = re.compile(r"^(?:\+?237)?(6\d{8})$")


class Envoi(BaseModel):
    emails: list[str] = Field(min_length=1, max_length=config.MAX_INVITATIONS_PAR_ENVOI)
    service: str | None = Field(default=None, max_length=60)


class Inscription(BaseModel):
    prenom: str = Field(min_length=1, max_length=60)
    nom: str = Field(min_length=1, max_length=60)
    telephone: str
    mot_de_passe: str = Field(min_length=8, max_length=128)


def hacher(mot_de_passe: str) -> str:
    sel = secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", mot_de_passe.encode(), sel.encode(), 200_000).hex()
    return f"pbkdf2_sha256$200000${sel}${h}"


def _courriel_invitation(conn, org: dict, email: str, jeton: str, relance: int = 0) -> str:
    lien = f"{URL_PUBLIQUE}/rejoindre/{jeton}"
    sujet = (f"Rappel : " if relance else "") + f"{org['nom']} vous invite sur MboaRide"
    corps = (f"Bonjour,\n\n{org['nom']} vous invite à rejoindre son cercle de covoiturage sur "
             f"MboaRide : vos trajets domicile-travail entre collègues, à prix partagé.\n\n"
             f"Pour rejoindre le cercle (lien valable 30 jours) :\n{lien}\n\n"
             f"Si vous n'avez pas encore de compte, vous le créerez depuis ce lien.\n")
    return envoyer_courriel(conn, email, sujet, corps)


def _expirer(conn, id_org: int) -> None:
    conn.execute("UPDATE invitation SET statut = 'expiree' WHERE id_organisation = %s "
                 "AND statut = 'envoyee' AND expire_le < now()", (id_org,))


# --------------------------------------------------------------------------- US13
@router.get("/moi/organisations")
def mes_organisations(u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return conn.execute(
        """SELECT o.id_organisation, o.nom, o.type_organisation, a.role
             FROM appartenance a JOIN organisation o USING (id_organisation)
            WHERE a.id_utilisateur = %s ORDER BY o.nom""", (u["id_utilisateur"],)).fetchall()


@router.post("/organisations/{id_org}/invitations", status_code=201)
def inviter(id_org: int, body: Envoi, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    org = exiger_admin(conn, u["id_utilisateur"], id_org)
    _expirer(conn, id_org)
    domaine = (org["domaine_email"] or "").lower()
    envoyees, ecartees, vus = [], [], set()
    statuts_envoi: dict[str, int] = {}
    for brut in body.emails:
        morceaux = re.split(r"[;\t]", brut, maxsplit=1)
        email = morceaux[0].strip().lower()
        service = (morceaux[1].strip() if len(morceaux) > 1 else "") or (body.service or "").strip() or None
        if not email:
            continue
        if email in vus:
            ecartees.append({"email": email, "motif": "doublon dans la liste"})
            continue
        vus.add(email)
        if not EMAIL.match(email):
            ecartees.append({"email": email, "motif": "adresse invalide"})
            continue
        if domaine and not email.endswith("@" + domaine):
            ecartees.append({"email": email, "motif": f"hors du domaine {domaine}"})
            continue
        membre = conn.execute(
            """SELECT 1 FROM utilisateur us JOIN appartenance a USING (id_utilisateur)
                WHERE lower(us.email) = %s AND a.id_organisation = %s""", (email, id_org)).fetchone()
        if membre:
            ecartees.append({"email": email, "motif": "déjà membre"})
            continue
        existante = conn.execute("SELECT statut FROM invitation WHERE id_organisation = %s AND email = %s",
                                 (id_org, email)).fetchone()
        jeton = secrets.token_hex(16)
        if existante and existante["statut"] == "envoyee":
            ecartees.append({"email": email, "motif": "déjà invitée, utilisez la relance"})
            continue
        if existante:   # expirée ou annulée : on renouvelle
            conn.execute(
                """UPDATE invitation SET jeton = %s, statut = 'envoyee', envoyee_le = now(),
                       expire_le = now() + INTERVAL '30 days', relances = 0, id_invite_par = %s,
                       service = %s
                   WHERE id_organisation = %s AND email = %s""",
                (jeton, u["id_utilisateur"], service, id_org, email))
        else:
            conn.execute("INSERT INTO invitation (id_organisation, email, jeton, id_invite_par, service) "
                         "VALUES (%s, %s, %s, %s, %s)", (id_org, email, jeton, u["id_utilisateur"], service))
        envoi = _courriel_invitation(conn, org, email, jeton)
        statuts_envoi[envoi] = statuts_envoi.get(envoi, 0) + 1
        envoyees.append({"email": email, "service": service, "lien": f"/rejoindre/{jeton}", "courriel": envoi})
    if smtp_actif():
        note = f"{statuts_envoi.get('envoye', 0)} e-mail(s) envoyé(s)" + (
            f", {statuts_envoi['echec']} en échec : transmettez le lien affiché" if statuts_envoi.get("echec") else "")
    else:
        note = "Envoi simulé (aucun serveur SMTP configuré) : les e-mails sont dans la boîte d'envoi de la démo."
    return {"envoyees": envoyees, "ecartees": ecartees, "note": note}


@router.get("/organisations/{id_org}/invitations")
def lister_invitations(id_org: int, statut: str | None = None, u: dict = Depends(utilisateur_courant),
                       conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    exiger_admin(conn, u["id_utilisateur"], id_org)
    _expirer(conn, id_org)
    rows = conn.execute(
        """SELECT i.id_invitation, i.email, i.statut, i.envoyee_le, i.acceptee_le, i.expire_le,
                  i.relances, i.service, us.prenom || ' ' || us.nom AS membre,
                  (SELECT count(*) FROM v_trajet_partage v
                    WHERE v.id_demandeur = i.id_utilisateur AND v.id_organisation = i.id_organisation)
                    AS trajets
             FROM invitation i LEFT JOIN utilisateur us ON us.id_utilisateur = i.id_utilisateur
            WHERE i.id_organisation = %s AND (%s::text IS NULL OR i.statut = %s)
            ORDER BY i.envoyee_le DESC, i.id_invitation DESC""", (id_org, statut, statut)).fetchall()
    return rows


@router.post("/organisations/{id_org}/invitations/{id_inv}/relance")
def relancer(id_org: int, id_inv: int, u: dict = Depends(utilisateur_courant),
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    org = exiger_admin(conn, u["id_utilisateur"], id_org)
    _expirer(conn, id_org)
    inv = conn.execute("SELECT * FROM invitation WHERE id_invitation = %s AND id_organisation = %s",
                       (id_inv, id_org)).fetchone()
    if inv is None:
        raise HTTPException(404, "Invitation introuvable")
    if inv["statut"] == "acceptee":
        raise HTTPException(409, "Invitation déjà acceptée")
    if inv["relances"] >= config.MAX_RELANCES:
        raise HTTPException(409, f"Nombre maximal de relances atteint ({config.MAX_RELANCES})")
    row = conn.execute(
        """UPDATE invitation SET relances = relances + 1, statut = 'envoyee',
               expire_le = now() + INTERVAL '30 days'
           WHERE id_invitation = %s RETURNING relances, jeton""", (id_inv,)).fetchone()
    envoi = _courriel_invitation(conn, org, inv["email"], row["jeton"], relance=row["relances"])
    return {"relances": row["relances"], "lien": f"/rejoindre/{row['jeton']}", "courriel": envoi}


def _invitation_valide(conn, jeton: str) -> dict:
    inv = conn.execute("SELECT i.*, o.nom FROM invitation i JOIN organisation o USING (id_organisation) "
                       "WHERE jeton = %s", (jeton,)).fetchone()
    if inv is None:
        raise HTTPException(404, "Lien d'invitation inconnu")
    if inv["statut"] == "acceptee":
        raise HTTPException(409, "Invitation déjà utilisée")
    if inv["statut"] != "envoyee" or inv["expire_le"] < conn.execute("SELECT now() n").fetchone()["n"]:
        raise HTTPException(410, "Invitation expirée : demandez une relance à votre administrateur")
    return inv


def _rejoindre(conn, inv: dict, id_utilisateur: int) -> dict:
    conn.execute("INSERT INTO appartenance (id_utilisateur, id_organisation, service) VALUES (%s, %s, %s) "
                 "ON CONFLICT (id_utilisateur, id_organisation) DO UPDATE "
                 "SET service = COALESCE(appartenance.service, EXCLUDED.service)",
                 (id_utilisateur, inv["id_organisation"], inv["service"]))
    conn.execute("UPDATE invitation SET statut = 'acceptee', acceptee_le = now(), id_utilisateur = %s "
                 "WHERE id_invitation = %s", (id_utilisateur, inv["id_invitation"]))
    return {"organisation": inv["nom"], "id_utilisateur": id_utilisateur,
            "message": f"Vous avez rejoint le cercle de {inv['nom']}"}


@router.get("/invitations/{jeton}")
def lire_invitation(jeton: str, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Informations publiques du lien : organisation, adresse invitée, compte existant ou non."""
    inv = _invitation_valide(conn, jeton)
    compte = conn.execute("SELECT 1 FROM utilisateur WHERE lower(email) = %s", (inv["email"],)).fetchone()
    return {"organisation": inv["nom"], "email": inv["email"], "service": inv["service"],
            "expire_le": inv["expire_le"], "compte_existant": compte is not None}


@router.post("/invitations/{jeton}/accepter")
def accepter(jeton: str, u: dict = Depends(utilisateur_courant),
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    inv = _invitation_valide(conn, jeton)
    if (u["email"] or "").lower() != inv["email"]:
        raise HTTPException(403, "Cette invitation est destinée à une autre adresse e-mail")
    return _rejoindre(conn, inv, u["id_utilisateur"])


@router.post("/invitations/{jeton}/inscription", status_code=201)
def inscription(jeton: str, body: Inscription, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Création de compte depuis le lien : l'adresse est celle de l'invitation, non modifiable."""
    inv = _invitation_valide(conn, jeton)
    m = TELEPHONE.match(re.sub(r"[\s.-]", "", body.telephone))
    if not m:
        raise HTTPException(422, "Numéro camerounais attendu : 6 suivi de 8 chiffres")
    telephone = "+237" + m.group(1)
    if conn.execute("SELECT 1 FROM utilisateur WHERE lower(email) = %s", (inv["email"],)).fetchone():
        raise HTTPException(409, "Un compte existe déjà pour cette adresse : connectez-vous puis acceptez")
    if conn.execute("SELECT 1 FROM utilisateur WHERE telephone = %s", (telephone,)).fetchone():
        raise HTTPException(409, "Ce numéro de téléphone est déjà utilisé")
    uid = conn.execute(
        """INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache)
           VALUES (%s, %s, %s, %s, %s) RETURNING id_utilisateur""",
        (body.nom.strip(), body.prenom.strip(), telephone, inv["email"], hacher(body.mot_de_passe))
    ).fetchone()["id_utilisateur"]
    return _rejoindre(conn, inv, uid)


@router.get("/organisations/{id_org}/adoption")
def adoption(id_org: int, u: dict = Depends(utilisateur_courant),
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    org = exiger_admin(conn, u["id_utilisateur"], id_org)
    _expirer(conn, id_org)
    inv = conn.execute(
        """SELECT count(*) AS envoyees,
                  count(*) FILTER (WHERE statut = 'acceptee') AS acceptees,
                  count(*) FILTER (WHERE statut = 'envoyee')  AS en_attente,
                  count(*) FILTER (WHERE statut = 'expiree')  AS expirees
             FROM invitation WHERE id_organisation = %s""", (id_org,)).fetchone()
    m = conn.execute(
        """SELECT count(*) AS membres,
                  count(*) FILTER (WHERE us.est_conducteur AND us.statut_agrement = 'actif') AS conducteurs,
                  count(*) FILTER (WHERE EXISTS (
                      SELECT 1 FROM v_trajet_partage v
                       WHERE (v.id_demandeur = a.id_utilisateur OR v.id_conducteur = a.id_utilisateur)
                         AND v.date_trajet BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE)) AS actifs_30j
             FROM appartenance a JOIN utilisateur us USING (id_utilisateur)
            WHERE a.id_organisation = %s""", (id_org,)).fetchone()
    mois = conn.execute(
        """WITH s AS (SELECT generate_series(date_trunc('month', min(date_adhesion)),
                                             date_trunc('month', CURRENT_DATE), '1 month')::date AS mois
                        FROM appartenance WHERE id_organisation = %(o)s)
           SELECT to_char(s.mois, 'YYYY-MM') AS mois,
                  (SELECT count(*) FROM appartenance a WHERE a.id_organisation = %(o)s
                      AND a.date_adhesion < s.mois + INTERVAL '1 month') AS membres_cumules,
                  (SELECT count(DISTINCT v.id_demandeur) FROM v_trajet_partage v
                    WHERE v.id_organisation = %(o)s AND date_trunc('month', v.date_trajet) = s.mois)
                    AS passagers_actifs
             FROM s ORDER BY s.mois""", {"o": id_org}).fetchall()
    services = conn.execute(
        """WITH m AS (
               SELECT COALESCE(a.service, 'Non renseigné') AS service, a.id_utilisateur
                 FROM appartenance a WHERE a.id_organisation = %(o)s),
           i AS (
               SELECT COALESCE(service, 'Non renseigné') AS service, count(*) AS en_attente
                 FROM invitation WHERE id_organisation = %(o)s AND statut = 'envoyee' GROUP BY 1)
           SELECT s.service,
                  (SELECT count(*) FROM m WHERE m.service = s.service) AS membres,
                  (SELECT count(*) FROM m WHERE m.service = s.service AND EXISTS (
                      SELECT 1 FROM v_trajet_partage v
                       WHERE (v.id_demandeur = m.id_utilisateur OR v.id_conducteur = m.id_utilisateur)
                         AND v.date_trajet BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE)) AS actifs_30j,
                  COALESCE((SELECT en_attente FROM i WHERE i.service = s.service), 0) AS invitations_en_attente
             FROM (SELECT service FROM m UNION SELECT service FROM i) s
            ORDER BY membres DESC, s.service""", {"o": id_org}).fetchall()
    effectif = org["effectif"]
    taux = round(m["membres"] / effectif, 3) if effectif else None
    objectif = float(org["objectif_adoption"])
    return {
        "organisation": org["nom"], "effectif": effectif,
        "membres": m["membres"], "conducteurs_agrees": m["conducteurs"],
        "membres_actifs_30j": m["actifs_30j"],
        "taux_adoption": taux, "objectif_adoption": objectif,
        "objectif_atteint": taux is not None and taux >= objectif,
        "manque_pour_objectif": max(0, round(objectif * effectif) - m["membres"]) if effectif else None,
        "invitations": {**inv, "taux_acceptation": round(inv["acceptees"] / inv["envoyees"], 3)
                        if inv["envoyees"] else None},
        "par_mois": mois,
        "par_service": services,
    }


# --------------------------------------------------------------------------- US14
def calcul_impact(rows: list[dict]) -> dict:
    km = litres = eco = depense = 0.0
    for r in rows:
        k = moteur.km_evites(r["depart_lat"], r["depart_lon"], r["arrivee_lat"], r["arrivee_lon"],
                             r["detour_km"])
        km += k
        litres += k * config.CONSO_REFERENCE_L100 / 100
        ref = (config.PRIX_CAR_INTERURBAIN_FCFA if r["type_trajet"] == "interurbain"
               else config.PRIX_TAXI_URBAIN_FCFA)
        eco += max(0, ref - r["prix_fcfa"])
        depense += r["prix_fcfa"]
    co2_haut = litres * config.CO2_KG_PAR_LITRE
    return {
        "trajets_partages": len(rows),
        "km_voiture_evites": round(km, 1),
        "litres_evites": round(litres, 1),
        "co2_evite_kg": {"prudent": round(co2_haut * config.PART_CONDUCTEURS_SEULS, 1),
                         "haut": round(co2_haut, 1)},
        "economies_employes_fcfa": round(eco),
        "depense_employes_fcfa": round(depense),
        "prix_moyen_fcfa": round(depense / len(rows)) if rows else None,
    }


@router.get("/organisations/{id_org}/impact")
def impact(id_org: int, du: date | None = Query(None), au: date | None = Query(None),
           u: dict = Depends(utilisateur_courant),
           conn: psycopg.Connection = Depends(get_conn)) -> dict:
    org = exiger_admin(conn, u["id_utilisateur"], id_org)
    au = au or date.today()
    du = du or (au.replace(day=1) - timedelta(days=1)).replace(day=1)   # mois précédent inclus
    if du > au:
        raise HTTPException(422, "La date de début doit précéder la date de fin")
    rows = conn.execute(
        """SELECT * FROM v_trajet_partage WHERE id_organisation = %s
              AND date_trajet BETWEEN %s AND %s ORDER BY date_trajet""", (id_org, du, au)).fetchall()
    total = calcul_impact(rows)
    par_mois: dict[str, list] = {}
    for r in rows:
        par_mois.setdefault(r["date_trajet"].strftime("%Y-%m"), []).append(r)
    mois = [{"mois": k, **calcul_impact(v)} for k, v in sorted(par_mois.items())]

    # Coût de l'abonnement : membres présents chaque mois de la période × tarif mensuel.
    mois_abonnes = conn.execute(
        """SELECT count(*) AS n FROM generate_series(date_trunc('month', %(du)s::date),
                                                     date_trunc('month', %(au)s::date), '1 month') m
             JOIN appartenance a ON a.id_organisation = %(o)s
                                AND a.date_adhesion < m + INTERVAL '1 month'""",
        {"du": du, "au": au, "o": id_org}).fetchone()["n"]
    nb_mois = (au.year - du.year) * 12 + au.month - du.month + 1
    abonnes = conn.execute("SELECT count(*) n FROM appartenance WHERE id_organisation = %s",
                           (id_org,)).fetchone()["n"]
    cout = mois_abonnes * org["tarif_mensuel_fcfa"] if org["abonnement_actif"] else 0
    return {
        "organisation": org["nom"], "du": du, "au": au, **total,
        "abonnement": {"abonnes": abonnes, "tarif_mensuel_fcfa": org["tarif_mensuel_fcfa"],
                       "mois": nb_mois, "mois_abonnes": mois_abonnes, "cout_fcfa": cout,
                       "economies_par_fcfa_d_abonnement":
                           round(total["economies_employes_fcfa"] / cout, 2) if cout else None},
        "par_mois": mois,
        "hypotheses": {
            "conso_voiture_seule_l100": config.CONSO_REFERENCE_L100,
            "co2_kg_par_litre": config.CO2_KG_PAR_LITRE,
            "scenario_prudent": "1 passager sur 3 aurait conduit seul",
            "scenario_haut": "chaque passager aurait conduit seul",
            "reference_prix_ville_fcfa": config.PRIX_TAXI_URBAIN_FCFA,
            "reference_prix_interurbain_fcfa": config.PRIX_CAR_INTERURBAIN_FCFA,
            "km_evites": "distance du trajet du passager moins le détour du conducteur",
        },
    }


def _fr(x) -> str:
    return "" if x is None else str(x).replace(".", ",")


@router.get("/organisations/{id_org}/impact.csv")
def impact_csv(id_org: int, du: date | None = Query(None), au: date | None = Query(None),
               u: dict = Depends(utilisateur_courant),
               conn: psycopg.Connection = Depends(get_conn)) -> Response:
    """Bilan de la période au format CSV (séparateur point-virgule, décimales à virgule)."""
    i = impact(id_org, du, au, u, conn)
    out = io.StringIO()
    w = csv.writer(out, delimiter=";")
    w.writerow([f"MboaRide · Bilan d'impact · {i['organisation']}", f"du {i['du']} au {i['au']}"])
    w.writerow([])
    w.writerow(["Mois", "Trajets partagés", "Km voiture évités", "Litres évités",
                "CO2 évité prudent (kg)", "CO2 évité haut (kg)", "Économies employés (FCFA)",
                "Dépense employés (FCFA)", "Prix moyen (FCFA)"])
    for m in i["par_mois"] + [{"mois": "Total", **{k: i[k] for k in i if k not in ("par_mois",)}}]:
        w.writerow([m["mois"], m["trajets_partages"], _fr(m["km_voiture_evites"]), _fr(m["litres_evites"]),
                    _fr(m["co2_evite_kg"]["prudent"]), _fr(m["co2_evite_kg"]["haut"]),
                    m["economies_employes_fcfa"], m["depense_employes_fcfa"], m["prix_moyen_fcfa"] or ""])
    a = i["abonnement"]
    w.writerow([])
    w.writerow(["Abonnés", a["abonnes"]])
    w.writerow(["Coût de l'abonnement sur la période (FCFA)", a["cout_fcfa"]])
    w.writerow(["Économies des employés par FCFA d'abonnement", _fr(a["economies_par_fcfa_d_abonnement"])])
    w.writerow([])
    w.writerow(["Hypothèses"])
    for k, v in i["hypotheses"].items():
        w.writerow([k.replace("_", " "), _fr(v) if isinstance(v, float) else v])
    nom = f"mboaride_impact_{i['du']}_{i['au']}.csv"
    return Response("\ufeff" + out.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{nom}"'})

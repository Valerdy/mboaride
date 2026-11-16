"""US17 et US19 · Comptes élèves et notifications aux parents.

US17 · « Créer un compte élève pour mes enfants de 12 ans et plus et autoriser leurs
trajets, pour garder le contrôle de qui les transporte. »
US19 · « Recevoir une notification au départ et à l'arrivée à l'école, pour être rassuré. »

Critères d'acceptation :
  1. Le parent crée un compte élève avec le prénom, l'âge déclaré et l'établissement ;
     l'âge hors de 12 à 17 ans est refusé avec un message clair (422).
  2. Le parent ne voit et ne modifie que ses propres élèves (404 sinon).
  3. Retirer l'autorisation empêche toute nouvelle réservation pour cet élève : la règle
     est tenue par le déclencheur `autorisation_eleve` de la base, pas seulement ici.
  4. Le journal d'un élève rassemble ses réservations et les notifications de départ,
     d'arrivée et de retard, de la plus récente à la plus ancienne.
  5. Les notifications de départ et d'arrivée sont simulées (US19 marquée « Simulé »
     dans le document de vision) : un point d'entrée de démonstration les produit pour
     la dernière réservation confirmée, en respectant les préférences de l'élève.
"""

from __future__ import annotations

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..db import get_conn
from ..securite import utilisateur_courant

router = APIRouter(prefix="/api/moi", tags=["US17 · US19 Comptes élèves"])

AGE_MIN, AGE_MAX = 12, 17


class NouvelEleve(BaseModel):
    prenom: str = Field(min_length=2, max_length=60)
    age: int = Field(ge=AGE_MIN, le=AGE_MAX,
                     description=f"Âge déclaré, de {AGE_MIN} à {AGE_MAX} ans")
    id_etablissement: int | None = None


class Autorisation(BaseModel):
    active: bool


def _eleve(conn: psycopg.Connection, id_eleve: int, id_parent: int) -> dict:
    row = conn.execute(
        """SELECT e.*, o.nom AS etablissement
             FROM compte_eleve e LEFT JOIN organisation o ON o.id_organisation = e.id_etablissement
            WHERE e.id_eleve = %s AND e.id_parent = %s""", (id_eleve, id_parent)).fetchone()
    if row is None:
        raise HTTPException(404, "Élève introuvable dans vos comptes")
    return row


def _vue(row: dict) -> dict:
    return {"id_eleve": row["id_eleve"], "prenom": row["prenom"], "age": row["age_declare"],
            "etablissement": row["etablissement"], "id_etablissement": row["id_etablissement"],
            "autorisation_active": row["autorisation_active"],
            "notifier_depart": row["notifier_depart"], "notifier_arrivee": row["notifier_arrivee"]}


@router.get("/eleves")
def mes_eleves(u: dict = Depends(utilisateur_courant),
               conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    rows = conn.execute(
        """SELECT e.*, o.nom AS etablissement
             FROM compte_eleve e LEFT JOIN organisation o ON o.id_organisation = e.id_etablissement
            WHERE e.id_parent = %s ORDER BY e.prenom""", (u["id_utilisateur"],)).fetchall()
    return [_vue(r) for r in rows]


@router.post("/eleves", status_code=201)
def creer_eleve(body: NouvelEleve, u: dict = Depends(utilisateur_courant),
                conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if body.id_etablissement is not None and not conn.execute(
            "SELECT 1 FROM organisation WHERE id_organisation = %s "
            "AND type_organisation IN ('etablissement_scolaire', 'campus')",
            (body.id_etablissement,)).fetchone():
        raise HTTPException(422, "Établissement inconnu")
    row = conn.execute(
        """INSERT INTO compte_eleve (id_parent, id_etablissement, prenom, age_declare)
           VALUES (%s, %s, %s, %s) RETURNING id_eleve""",
        (u["id_utilisateur"], body.id_etablissement, body.prenom.strip(), body.age)).fetchone()
    return _vue(_eleve(conn, row["id_eleve"], u["id_utilisateur"]))


@router.put("/eleves/{id_eleve}/autorisation")
def autoriser(id_eleve: int, body: Autorisation, u: dict = Depends(utilisateur_courant),
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    _eleve(conn, id_eleve, u["id_utilisateur"])
    conn.execute("UPDATE compte_eleve SET autorisation_active = %s WHERE id_eleve = %s",
                 (body.active, id_eleve))
    return _vue(_eleve(conn, id_eleve, u["id_utilisateur"]))


@router.get("/eleves/{id_eleve}/journal")
def journal(id_eleve: int, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Réservations et notifications de l'élève, de la plus récente à la plus ancienne."""
    _eleve(conn, id_eleve, u["id_utilisateur"])
    lignes = conn.execute(
        """SELECT 'reservation' AS type, r.cree_le AS horodatage,
                  'Place confirmée pour le ' || to_char(r.date_trajet, 'DD/MM')
                      || ' à ' || to_char(r.heure_prise_en_charge, 'HH24:MI') AS libelle,
                  c.prenom AS conducteur
             FROM reservation r
             JOIN demande d  ON d.id_demande = r.id_demande
             JOIN trajet t   ON t.id_trajet = r.id_trajet
             JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur
            WHERE d.id_eleve = %(e)s AND r.statut = 'confirmee'
            UNION ALL
           SELECT n.type, n.cree_le, n.message, NULL
             FROM notification n
            WHERE n.id_eleve = %(e)s AND n.type IN ('depart', 'arrivee', 'retard')
            ORDER BY horodatage DESC
            LIMIT 40""", {"e": id_eleve}).fetchall()
    return [{"type": r["type"], "horodatage": r["horodatage"].strftime("%d/%m %H:%M"),
             "libelle": r["libelle"], "conducteur": r["conducteur"]} for r in lignes]


@router.post("/eleves/{id_eleve}/simuler-trajet", status_code=201)
def simuler_trajet(id_eleve: int, u: dict = Depends(utilisateur_courant),
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """US19 simulée : produit les notifications de départ et d'arrivée du dernier trajet."""
    eleve = _eleve(conn, id_eleve, u["id_utilisateur"])
    r = conn.execute(
        """SELECT r.id_reservation, r.heure_prise_en_charge, r.heure_arrivee_estimee,
                  d.depart_libelle, d.arrivee_libelle, c.prenom AS conducteur
             FROM reservation r
             JOIN demande d ON d.id_demande = r.id_demande
             JOIN trajet t  ON t.id_trajet = r.id_trajet
             JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur
            WHERE d.id_eleve = %s AND r.statut = 'confirmee'
            ORDER BY r.date_trajet DESC, r.id_reservation DESC LIMIT 1""", (id_eleve,)).fetchone()
    if r is None:
        raise HTTPException(409, f"Aucune réservation confirmée pour {eleve['prenom']}")
    envoyees = []
    if eleve["notifier_depart"]:
        envoyees.append(("depart", f"{eleve['prenom']} est montée à bord à {r['depart_libelle']} "
                                   f"à {r['heure_prise_en_charge']:%H:%M} avec {r['conducteur']}."))
    if eleve["notifier_arrivee"]:
        envoyees.append(("arrivee", f"{eleve['prenom']} est arrivée à {r['arrivee_libelle']} "
                                    f"à {r['heure_arrivee_estimee']:%H:%M}."))
    for type_, message in envoyees:
        conn.execute(
            """INSERT INTO notification (id_utilisateur, type, message, id_eleve, id_reservation)
               VALUES (%s, %s, %s, %s, %s)""",
            (u["id_utilisateur"], type_, message, id_eleve, r["id_reservation"]))
    return {"id_eleve": id_eleve, "notifications": [m for _, m in envoyees]}

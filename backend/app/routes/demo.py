"""SR-47 · Scénarios de démonstration, rejouables à volonté devant le jury.

  nominal        Grâce choisit une offre, voit le prix détaillé, confirme et paie (US02, US09, US10)
  annulation     Le conducteur de Grâce annule ; elle est remboursée et réaffectée (US07, US10)
  aucune_offre   Nadège n'a aucune offre : l'appli explique pourquoi et quoi changer
  elargissement  Grâce limitée à ses collègues ne trouve rien ; en élargissant au réseau
                 public, une offre apparaît (US02, US09)

Chaque préparation remet les données du scénario dans leur état de départ, sans toucher au
reste de la base. Les étapes renvoyées servent de fil conducteur pendant la soutenance.
"""

from __future__ import annotations

from datetime import date

import psycopg
from fastapi import APIRouter, Depends, HTTPException

from ..db import get_conn
from .prix import offres_valides, reserver

router = APIRouter(prefix="/api/demo", tags=["SR-47 · Scénarios de démo"])

GRACE, NADEGE = 2, 5
JOUR_NOMINAL = date(2026, 11, 16)
JOUR_ELARGI = date(2026, 11, 18)


def _purger_demande(conn, id_demande: int) -> None:
    resas = "SELECT id_reservation FROM reservation WHERE id_demande = %s"
    conn.execute(f"DELETE FROM paiement WHERE id_reservation IN ({resas})", (id_demande,))
    conn.execute("DELETE FROM reservation WHERE id_demande = %s", (id_demande,))


def _demande_grace(conn, depart, lat, lon, arrivee, alat, alon, tot, tard, jour, cercle) -> int:
    d = conn.execute("SELECT id_demande FROM demande WHERE id_demandeur = %s AND date_unique = %s "
                     "AND depart_libelle = %s AND arrivee_libelle = %s",
                     (GRACE, jour, depart, arrivee)).fetchone()
    if d:
        _purger_demande(conn, d["id_demande"])
        conn.execute("""UPDATE demande SET statut = 'ouverte', mode_reservation = 'manuel', cercle_max = %s,
                            prix_max_fcfa = 400, arrivee_au_plus_tot = %s, arrivee_au_plus_tard = %s
                         WHERE id_demande = %s""", (cercle, tot, tard, d["id_demande"]))
        return d["id_demande"]
    return conn.execute(
        """INSERT INTO demande (id_demandeur, id_organisation, depart_libelle, depart_lat, depart_lon,
               arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot, arrivee_au_plus_tard,
               date_unique, prix_max_fcfa, cercle_max, statut)
           VALUES (%s, 1, %s, %s, %s, %s, %s, %s, %s, %s, %s, 400, %s, 'ouverte')
        RETURNING id_demande""",
        (GRACE, depart, lat, lon, arrivee, alat, alon, tot, tard, jour, cercle)).fetchone()["id_demande"]


def _remise_a_zero(conn) -> None:
    conn.execute("DELETE FROM indisponibilite_trajet WHERE date_trajet IN (%s, %s)", (JOUR_NOMINAL, JOUR_ELARGI))
    conn.execute("DELETE FROM notification WHERE id_utilisateur IN "
                 "(SELECT id_utilisateur FROM utilisateur WHERE id_utilisateur IN (%s, %s) "
                 " OR telephone LIKE '+2376999%%')", (GRACE, NADEGE))


def nominal(conn) -> dict:
    _remise_a_zero(conn)
    d = _demande_grace(conn, "Makepe", 4.081, 9.752, "Bonanjo", 4.042, 9.689, "07:20", "08:00",
                       JOUR_NOMINAL, "partenaires")
    return {"utilisateur": GRACE, "onglet": "prix", "id_demande": d, "etapes": [
        "Grâce (Entreprise A) a demandé Makepe → Bonanjo pour le lundi 16 novembre, arrivée entre 07:20 et 08:00, 400 FCFA au plus.",
        "Onglet « Mes exigences » : montrer climatisation souhaitée, cercle partenaires, mode manuel.",
        "Onglet « Prix et confirmation » : les offres sont triées, chacune avec son prix détaillé ligne par ligne.",
        "Choisir la première offre confirmable, puis le bouton « Confirmer » qui rappelle le prix.",
        "Payer avec MTN MoMo au 6 77 12 34 56, puis « Valider avec mon code » : reçu avec la part reversée au conducteur.",
        "Variante : taper un numéro Orange (6 99…) avec MTN choisi pour montrer le contrôle, ou « Solde insuffisant » pour montrer l'échec et la nouvelle tentative.",
    ]}


def annulation(conn) -> dict:
    prep = nominal(conn)
    d = conn.execute("SELECT * FROM demande WHERE id_demande = %s", (prep["id_demande"],)).fetchone()
    conn.execute("UPDATE demande SET mode_reservation = 'autonome' WHERE id_demande = %s", (d["id_demande"],))
    d = {**d, "mode_reservation": "autonome"}
    offres = [o for o in offres_valides(conn, d, jour=JOUR_NOMINAL) if o["confirmable"]]
    if len(offres) < 2:
        raise HTTPException(409, "Pas assez d'offres dans les données de démo pour ce scénario")
    choix = offres[0]
    r = reserver(conn, d, choix, JOUR_NOMINAL)
    conn.execute("""UPDATE paiement SET statut = 'reussi', paye_le = now(), operateur = 'mtn',
                        telephone_payeur = '+237677123456', reference_transaction = 'MBR-DEMO' || id_paiement,
                        initie_le = now(), tentatives = 1
                     WHERE id_paiement = %s""", (r["id_paiement"],))
    cond = conn.execute("SELECT t.id_conducteur, u.prenom FROM trajet t JOIN utilisateur u "
                        "ON u.id_utilisateur = t.id_conducteur WHERE t.id_trajet = %s",
                        (choix["id_trajet"],)).fetchone()
    return {"utilisateur": cond["id_conducteur"], "onglet": "trajets", "id_demande": d["id_demande"],
            "id_trajet": choix["id_trajet"], "date_trajet": JOUR_NOMINAL, "etapes": [
        f"Grâce est en mode autonome : elle a été placée avec {cond['prenom']} le 16 novembre "
        f"pour {choix['prix_fcfa']} FCFA, déjà payés par Mobile Money.",
        f"Connecté en tant que {cond['prenom']} (conducteur), onglet « Mes trajets » : annuler le 16/11.",
        "Le paiement de Grâce est remboursé, et le système la réaffecte seul à la meilleure offre restante.",
        "Repasser sur Grâce : la cloche montre l'annulation, le remboursement et le nouveau conducteur ; "
        "le nouveau trajet est à payer.",
    ]}


def aucune_offre(conn) -> dict:
    _remise_a_zero(conn)
    d = conn.execute("SELECT id_demande FROM demande WHERE id_demandeur = %s ORDER BY id_demande LIMIT 1",
                     (NADEGE,)).fetchone()
    if d is None:
        raise HTTPException(409, "Demande de Nadège absente des données d'exemple")
    _purger_demande(conn, d["id_demande"])
    conn.execute("UPDATE demande SET statut = 'ouverte' WHERE id_demande = %s", (d["id_demande"],))
    return {"utilisateur": NADEGE, "onglet": "prix", "id_demande": d["id_demande"], "etapes": [
        "Nadège (Campus C) veut aller de Bonabéri au campus, arrivée 07:15 à 07:30, 300 FCFA au plus, réseau public accepté.",
        "Onglet « Prix et confirmation » : aucune offre ne convient.",
        "L'appli ne s'arrête pas à « aucun résultat » : elle dit combien de trajets ont été examinés et pourquoi chacun est écarté.",
        "Elle propose ce qui débloquerait la situation (fenêtre, budget) ; la demande reste ouverte pour les prochains conducteurs.",
    ]}


def elargissement(conn) -> dict:
    _remise_a_zero(conn)
    d = _demande_grace(conn, "Makepe", 4.081, 9.752, "Bonapriso", 4.033, 9.695, "06:55", "07:15",
                       JOUR_ELARGI, "organisation")
    return {"utilisateur": GRACE, "onglet": "prix", "id_demande": d, "etapes": [
        "Grâce demande Makepe → Bonapriso pour le 18 novembre, mais seulement avec ses collègues (cercle organisation).",
        "Onglet « Prix et confirmation » : aucune offre, et l'appli indique qu'un conducteur vérifié du réseau public fait ce trajet.",
        "Cliquer le bouton « Élargir au cercle public » : l'offre apparaît, avec la commission de 10 % affichée dans le détail du prix.",
        "Rappeler que tout conducteur du réseau public est agréé (identité, permis, casier, assurance).",
    ]}


SCENARIOS = {
    "nominal": ("Parcours nominal", nominal),
    "annulation": ("Annulation du conducteur", annulation),
    "aucune_offre": ("Aucune offre", aucune_offre),
    "elargissement": ("Élargissement du cercle", elargissement),
}


@router.get("/scenarios")
def lister() -> list[dict]:
    return [{"code": k, "titre": v[0]} for k, v in SCENARIOS.items()]


@router.post("/scenarios/{code}")
def preparer(code: str, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if code not in SCENARIOS:
        raise HTTPException(404, "Scénario inconnu")
    titre, fn = SCENARIOS[code]
    return {"code": code, "titre": titre, **fn(conn)}


@router.get("/courriels")
def courriels(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Boîte d'envoi : les derniers courriels envoyés ou simulés par la plateforme."""
    return conn.execute("SELECT * FROM courriel ORDER BY id_courriel DESC LIMIT 20").fetchall()

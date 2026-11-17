"""Déroulement d'une course et versement au conducteur.

  1. Le conducteur démarre la course le jour du trajet : ses passagers payés sont prévenus.
  2. Le passager suit la course sur la carte. Arrivé à destination, il valide la fin de la
     course, note le conducteur et peut laisser un commentaire.
  3. Quand chaque passager payé de l'équipage a validé, MboaRide verse au conducteur, dans
     son portefeuille, le prix de chaque place moins la commission de 10 %. Avec le
     virement automatique, la somme part aussitôt vers son compte Mobile Money.
  4. Une fin de course que personne ne valide l'est d'office 24 heures après l'arrivée
     (MBOARIDE_VALIDATION_AUTO_HEURES), pour que le conducteur soit payé.

En démonstration (MBOARIDE_SIMULATION=1), une course peut démarrer avant son jour et le
passager peut valider sans que le conducteur l'ait démarrée : de quoi tout essayer sans
attendre la date ni se déplacer.
"""

from __future__ import annotations

from datetime import date, timedelta

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import config
from .. import portefeuille as pf
from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .paiement import OPERATEURS
from .prix import roule_le

router = APIRouter(prefix="/api/moi", tags=["Course et fin de course"])

MERCI = "Merci d'avoir voyagé avec MboaRide !"


class Jour(BaseModel):
    id_trajet: int
    date_trajet: date


class FinDeCourse(BaseModel):
    note: int = Field(ge=1, le=5, description="Note du conducteur et de la course, de 1 à 5")
    commentaire: str | None = Field(default=None, max_length=500)
    signalement_grave: bool = False


def _hhmm(t) -> str | None:
    return t.strftime("%H:%M") if t is not None else None


def passagers_payes(conn, id_trajet: int, jour: date) -> list[dict]:
    """Passagers qui ont payé leur place ce jour-là : ce sont eux qui valident la fin."""
    return conn.execute(
        """SELECT r.id_reservation, r.statut, r.fin_validee_le, r.heure_prise_en_charge, d.id_demandeur,
                  u.prenom, u.nom, p.id_paiement, p.montant_fcfa, p.commission_fcfa, p.verse_le,
                  e.note
             FROM reservation r JOIN demande d USING (id_demande)
             JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur
             JOIN paiement p ON p.id_reservation = r.id_reservation AND p.statut = 'reussi'
             LEFT JOIN evaluation e ON e.id_reservation = r.id_reservation AND e.id_auteur = d.id_demandeur
            WHERE r.id_trajet = %s AND r.date_trajet = %s AND r.statut IN ('confirmee', 'terminee')
            ORDER BY r.heure_prise_en_charge, r.id_reservation""", (id_trajet, jour)).fetchall()


def _course(conn, id_trajet: int, jour: date) -> dict | None:
    return conn.execute("SELECT * FROM course WHERE id_trajet = %s AND date_trajet = %s",
                        (id_trajet, jour)).fetchone()


def etat_course(conn, t: dict, jour: date) -> dict:
    c = _course(conn, t["id_trajet"], jour)
    passagers = passagers_payes(conn, t["id_trajet"], jour)
    part = sum(p["montant_fcfa"] - p["commission_fcfa"] for p in passagers)
    return {
        "id_trajet": t["id_trajet"], "date_trajet": jour.isoformat(),
        "trajet": f"{t['depart_libelle']} → {t['arrivee_libelle']}",
        "statut": c["statut"] if c else "a_demarrer",
        "demarree_le": c["demarree_le"] if c else None, "arrivee_le": c["arrivee_le"] if c else None,
        "passagers": [{"id_reservation": p["id_reservation"], "prenom": p["prenom"], "nom": p["nom"],
                       "fin_validee": p["fin_validee_le"] is not None, "note": p["note"],
                       "montant_fcfa": p["montant_fcfa"]} for p in passagers],
        "validations": sum(p["fin_validee_le"] is not None for p in passagers),
        "total_paye_fcfa": sum(p["montant_fcfa"] for p in passagers),
        "commission_fcfa": sum(p["commission_fcfa"] for p in passagers),
        "montant_conducteur_fcfa": part,
        "verse": bool(passagers) and all(p["verse_le"] is not None for p in passagers),
    }


def regler_si_complet(conn, id_trajet: int, jour: date) -> dict | None:
    """Verse au conducteur sa part quand tous les passagers payés ont validé la fin.

    Renvoie le détail du versement, ou None s'il manque des validations (ou si tout est
    déjà versé)."""
    passagers = passagers_payes(conn, id_trajet, jour)
    if not passagers or any(p["fin_validee_le"] is None for p in passagers):
        return None
    a_verser = [p for p in passagers if p["verse_le"] is None]
    if not a_verser:
        return None
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s", (id_trajet,)).fetchone()
    total = sum(p["montant_fcfa"] - p["commission_fcfa"] for p in a_verser)
    commission = sum(p["commission_fcfa"] for p in a_verser)
    for p in a_verser:
        conn.execute("UPDATE paiement SET verse_le = now(), montant_verse_fcfa = %s WHERE id_paiement = %s",
                     (p["montant_fcfa"] - p["commission_fcfa"], p["id_paiement"]))
        conn.execute("INSERT INTO commission_mboaride (id_paiement, montant_fcfa) VALUES (%s, %s) "
                     "ON CONFLICT DO NOTHING", (p["id_paiement"], p["commission_fcfa"]))
    conn.execute(
        """INSERT INTO course (id_trajet, date_trajet, statut, reglee_le) VALUES (%s, %s, 'reglee', now())
           ON CONFLICT (id_trajet, date_trajet) DO UPDATE
              SET statut = 'reglee', reglee_le = now(), arrivee_le = coalesce(course.arrivee_le, now())""",
        (id_trajet, jour))
    ref = pf.reference("GAIN")
    trajet = f"{t['depart_libelle']} → {t['arrivee_libelle']}"
    pf.mouvement(conn, t["id_conducteur"], "gain", total,
                 f"Course {trajet} du {jour:%d/%m} : {len(a_verser)} passager(s), "
                 f"commission MboaRide de {commission} FCFA déduite", ref)
    notifier(conn, t["id_conducteur"], "versement",
             f"Tout l'équipage a validé la fin de la course {trajet} du {jour:%d/%m} : {total} FCFA versés "
             f"dans votre portefeuille (commission MboaRide de 10 % : {commission} FCFA).")
    virement = None
    p = pf.ouvrir(conn, t["id_conducteur"])
    compte = pf.compte_par_defaut(conn, t["id_conducteur"])
    if p["virement_auto"] and compte is not None:
        op = OPERATEURS[compte["operateur"]]["libelle"]
        vir = pf.reference("VIR")
        pf.mouvement(conn, t["id_conducteur"], "retrait", -total,
                     f"Virement automatique vers {op} {pf.numero_lisible(compte['telephone'])}", vir)
        notifier(conn, t["id_conducteur"], "portefeuille",
                 f"{total} FCFA virés automatiquement vers votre compte {op} (réf. {vir}).")
        virement = {"operateur": op, "telephone": compte["telephone"], "reference": vir}
    return {"montant_verse_fcfa": total, "commission_fcfa": commission, "passagers": len(a_verser),
            "reference": ref, "virement_mobile_money": virement}


def regler_courses_echues(conn, id_conducteur: int | None = None) -> int:
    """Valide d'office les fins de course en attente depuis plus de VALIDATION_AUTO_HEURES."""
    courses = conn.execute(
        f"""SELECT c.id_trajet, c.date_trajet FROM course c JOIN trajet t USING (id_trajet)
             WHERE c.statut IN ('en_cours', 'arrivee')
               AND coalesce(c.arrivee_le, c.demarree_le) < now() - make_interval(hours => %s)
               {"AND t.id_conducteur = %s" if id_conducteur is not None else ""}""",
        (config.VALIDATION_AUTO_HEURES, *([id_conducteur] if id_conducteur is not None else []))).fetchall()
    for c in courses:
        for p in passagers_payes(conn, c["id_trajet"], c["date_trajet"]):
            if p["fin_validee_le"] is None:
                conn.execute("UPDATE reservation SET statut = 'terminee', fin_validee_le = now() "
                             "WHERE id_reservation = %s", (p["id_reservation"],))
                notifier(conn, p["id_demandeur"], "fin_course",
                         f"Votre course du {c['date_trajet']:%d/%m} a été clôturée automatiquement. {MERCI}")
        regler_si_complet(conn, c["id_trajet"], c["date_trajet"])
    return len(courses)


# --- Conducteur --------------------------------------------------------------------------------

def _trajet_du_conducteur(conn, id_trajet: int, u: dict) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s AND id_conducteur = %s",
                     (id_trajet, u["id_utilisateur"])).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    return t


@router.get("/conducteur/course")
def etat(id_trajet: int, date_trajet: date, u: dict = Depends(utilisateur_courant),
         conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return etat_course(conn, _trajet_du_conducteur(conn, id_trajet, u), date_trajet)


@router.post("/conducteur/course/demarrer")
def demarrer(body: Jour, u: dict = Depends(utilisateur_courant),
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = _trajet_du_conducteur(conn, body.id_trajet, u)
    aujourd_hui = date.today()
    if not config.SIMULATION and body.date_trajet != aujourd_hui:
        raise HTTPException(409, "La course se démarre le jour du trajet")
    if config.SIMULATION and not aujourd_hui - timedelta(days=1) <= body.date_trajet <= aujourd_hui + timedelta(days=8):
        raise HTTPException(409, "Date trop éloignée pour démarrer la course")
    if not roule_le(t, body.date_trajet) or conn.execute(
            "SELECT 1 FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s",
            (t["id_trajet"], body.date_trajet)).fetchone():
        raise HTTPException(409, "Ce trajet n'a pas lieu à cette date")
    passagers = passagers_payes(conn, t["id_trajet"], body.date_trajet)
    if not passagers:
        raise HTTPException(409, "Aucun passager n'a encore payé sa place pour ce trajet")
    c = _course(conn, t["id_trajet"], body.date_trajet)
    if c is not None and c["statut"] == "reglee":
        raise HTTPException(409, "Cette course est déjà terminée et réglée")
    if c is None:
        conn.execute("INSERT INTO course (id_trajet, date_trajet) VALUES (%s, %s)", (t["id_trajet"], body.date_trajet))
        for p in passagers:
            r = conn.execute("SELECT d.depart_libelle FROM reservation r JOIN demande d USING (id_demande) "
                             "WHERE r.id_reservation = %s", (p["id_reservation"],)).fetchone()
            lieu = t["point_ramassage"] if r["depart_libelle"] == t["depart_libelle"] and t["point_ramassage"] \
                else r["depart_libelle"]
            notifier(conn, p["id_demandeur"], "course",
                     f"{u['prenom']} a démarré la course : prise en charge vers "
                     f"{_hhmm(p['heure_prise_en_charge'])} à {lieu}. Suivez-le dans Mes trajets.")
    return etat_course(conn, t, body.date_trajet)


@router.post("/conducteur/course/arrivee")
def arrivee(body: Jour, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = _trajet_du_conducteur(conn, body.id_trajet, u)
    c = _course(conn, t["id_trajet"], body.date_trajet)
    if c is None:
        raise HTTPException(409, "Démarrez d'abord la course")
    if c["statut"] == "en_cours":
        conn.execute("UPDATE course SET statut = 'arrivee', arrivee_le = now() WHERE id_trajet = %s "
                     "AND date_trajet = %s", (t["id_trajet"], body.date_trajet))
        for p in passagers_payes(conn, t["id_trajet"], body.date_trajet):
            if p["fin_validee_le"] is None:
                notifier(conn, p["id_demandeur"], "fin_course",
                         f"Vous êtes arrivés à {t['arrivee_libelle']} : validez la fin de la course dans "
                         f"Mes trajets et notez {u['prenom']}. Il sera payé quand tout l'équipage aura validé.")
    return etat_course(conn, t, body.date_trajet)


# --- Passager ----------------------------------------------------------------------------------

def _reservation_du_passager(conn, id_reservation: int, u: dict) -> dict:
    r = conn.execute(
        """SELECT r.*, d.id_demandeur, d.depart_libelle, d.depart_lat, d.depart_lon,
                  d.arrivee_libelle, d.arrivee_lat, d.arrivee_lon,
                  t.id_conducteur, t.depart_libelle AS trajet_depart, t.arrivee_libelle AS trajet_arrivee,
                  t.depart_lat AS trajet_depart_lat, t.depart_lon AS trajet_depart_lon,
                  t.arrivee_lat AS trajet_arrivee_lat, t.arrivee_lon AS trajet_arrivee_lon,
                  t.heure_depart, t.point_ramassage, t.consignes_ramassage, t.attente_max_min,
                  uc.prenom AS conducteur_prenom, uc.nom AS conducteur_nom, uc.telephone AS conducteur_telephone,
                  v.marque_modele, v.immatriculation,
                  p.statut AS statut_paiement, p.verse_le
             FROM reservation r JOIN demande d USING (id_demande)
             JOIN trajet t ON t.id_trajet = r.id_trajet
             JOIN utilisateur uc ON uc.id_utilisateur = t.id_conducteur
             JOIN vehicule v ON v.id_vehicule = t.id_vehicule
             LEFT JOIN paiement p ON p.id_reservation = r.id_reservation
            WHERE r.id_reservation = %s""", (id_reservation,)).fetchone()
    if r is None or r["id_demandeur"] != u["id_utilisateur"]:
        raise HTTPException(404, "Trajet introuvable")
    return r


@router.get("/reservations/{id_reservation}/suivi")
def suivi(id_reservation: int, u: dict = Depends(utilisateur_courant),
          conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Tout ce qu'il faut pour suivre la course sur la carte et valider son arrivée."""
    r = _reservation_du_passager(conn, id_reservation, u)
    c = _course(conn, r["id_trajet"], r["date_trajet"])
    paye = r["statut_paiement"] == "reussi"
    meme_depart = r["depart_libelle"] == r["trajet_depart"]
    return {
        "id_reservation": id_reservation, "date_trajet": r["date_trajet"],
        "statut_reservation": r["statut"], "paye": paye,
        "statut_course": c["statut"] if c else "a_demarrer",
        "fin_validee": r["fin_validee_le"] is not None,
        "peut_valider": _peut_valider(r, c) is None,
        "conducteur": r["conducteur_prenom"],
        "conducteur_nom": r["conducteur_nom"],
        # Le numéro du conducteur n'est donné qu'aux passagers qui ont payé leur place.
        "conducteur_telephone": r["conducteur_telephone"] if paye else None,
        "vehicule": f"{r['marque_modele']} · {r['immatriculation']}",
        "prise_en_charge": _hhmm(r["heure_prise_en_charge"]), "arrivee": _hhmm(r["heure_arrivee_estimee"]),
        "prix_fcfa": r["prix_fcfa"],
        "point_ramassage": (r["point_ramassage"] if meme_depart else None) or r["depart_libelle"],
        "consignes_ramassage": r["consignes_ramassage"], "attente_max_min": r["attente_max_min"],
        "depart": {"libelle": r["depart_libelle"], "lat": float(r["depart_lat"]), "lon": float(r["depart_lon"])},
        "destination": {"libelle": r["arrivee_libelle"], "lat": float(r["arrivee_lat"]),
                        "lon": float(r["arrivee_lon"])},
        "conducteur_depart": {"libelle": r["trajet_depart"], "lat": float(r["trajet_depart_lat"]),
                              "lon": float(r["trajet_depart_lon"])},
        "conducteur_arrivee": {"libelle": r["trajet_arrivee"], "lat": float(r["trajet_arrivee_lat"]),
                               "lon": float(r["trajet_arrivee_lon"])},
    }


def _peut_valider(r: dict, c: dict | None) -> str | None:
    """Motif de refus de la validation de fin de course, ou None si elle est possible."""
    if r["statut"] == "annulee":
        return "Ce trajet a été annulé"
    if r["fin_validee_le"] is not None:
        return "Vous avez déjà validé la fin de cette course"
    if r["statut_paiement"] != "reussi":
        return "Payez d'abord votre place : la fin de course concerne les trajets payés"
    if c is None and r["date_trajet"] > date.today() and not config.SIMULATION:
        return "La course n'a pas encore commencé"
    return None


@router.post("/reservations/{id_reservation}/fin-de-course")
def valider_fin(id_reservation: int, body: FinDeCourse, u: dict = Depends(utilisateur_courant),
                conn: psycopg.Connection = Depends(get_conn)) -> dict:
    r = _reservation_du_passager(conn, id_reservation, u)
    c = _course(conn, r["id_trajet"], r["date_trajet"])
    refus = _peut_valider(r, c)
    if refus:
        raise HTTPException(409, refus)
    conn.execute("UPDATE reservation SET statut = 'terminee', fin_validee_le = now() WHERE id_reservation = %s",
                 (id_reservation,))
    commentaire = (body.commentaire or "").strip() or None
    conn.execute(
        """INSERT INTO evaluation (id_reservation, id_auteur, id_evalue, note, commentaire, signalement_grave)
           VALUES (%s, %s, %s, %s, %s, %s) ON CONFLICT (id_reservation, id_auteur) DO NOTHING""",
        (id_reservation, u["id_utilisateur"], r["id_conducteur"], body.note, commentaire, body.signalement_grave))
    notifier(conn, r["id_conducteur"], "fin_course",
             f"{u['prenom']} a validé la fin de la course du {r['date_trajet']:%d/%m} et vous a donné "
             f"{body.note}/5" + (f" : « {commentaire[:120]} »" if commentaire else "."))
    versement = regler_si_complet(conn, r["id_trajet"], r["date_trajet"])
    restants = [p["prenom"] for p in passagers_payes(conn, r["id_trajet"], r["date_trajet"])
                if p["fin_validee_le"] is None]
    return {"id_reservation": id_reservation, "etat": "termine", "message": MERCI,
            "conducteur": r["conducteur_prenom"], "note": body.note,
            "conducteur_paye": versement is not None or not restants,
            "en_attente_de": restants}

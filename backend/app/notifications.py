"""Notifications dans l'application et envoi de courriels.

Les courriels partent réellement par SMTP si MBOARIDE_SMTP_HOST est défini, par exemple
avec un compte Gmail et un mot de passe d'application :

    MBOARIDE_SMTP_HOST=smtp.gmail.com  MBOARIDE_SMTP_PORT=587
    MBOARIDE_SMTP_USER=adresse@gmail.com  MBOARIDE_SMTP_PASSWORD=motdepasse_application

Sinon l'envoi est simulé : le message est enregistré dans la table courriel et visible dans
la boîte d'envoi de la démo. Dans les deux cas, chaque envoi est tracé.
"""

from __future__ import annotations

import os
import smtplib
from email.message import EmailMessage

SMTP_HOST = os.environ.get("MBOARIDE_SMTP_HOST")
SMTP_PORT = int(os.environ.get("MBOARIDE_SMTP_PORT", "587"))
SMTP_USER = os.environ.get("MBOARIDE_SMTP_USER")
SMTP_PASSWORD = os.environ.get("MBOARIDE_SMTP_PASSWORD")
EXPEDITEUR = os.environ.get("MBOARIDE_EXPEDITEUR", SMTP_USER or "no-reply@mboaride.local")
URL_PUBLIQUE = os.environ.get("MBOARIDE_URL", "http://localhost:8000").rstrip("/")


def smtp_actif() -> bool:
    return bool(SMTP_HOST)


def envoyer_courriel(conn, destinataire: str, sujet: str, corps: str) -> str:
    """Envoie (ou simule) un courriel et le trace. Renvoie 'envoye', 'simule' ou 'echec'."""
    statut, erreur = "simule", None
    if smtp_actif():
        msg = EmailMessage()
        msg["From"], msg["To"], msg["Subject"] = EXPEDITEUR, destinataire, sujet
        msg.set_content(corps)
        try:
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as s:
                s.starttls()
                if SMTP_USER:
                    s.login(SMTP_USER, SMTP_PASSWORD or "")
                s.send_message(msg)
            statut = "envoye"
        except Exception as exc:          # l'invitation reste valable, le lien est affiché
            statut, erreur = "echec", str(exc)[:300]
    conn.execute("INSERT INTO courriel (destinataire, sujet, corps, statut, erreur) VALUES (%s, %s, %s, %s, %s)",
                 (destinataire, sujet, corps, statut, erreur))
    return statut


def notifier(conn, id_utilisateur: int, type_: str, message: str) -> None:
    conn.execute("INSERT INTO notification (id_utilisateur, type, message) VALUES (%s, %s, %s)",
                 (id_utilisateur, type_, message[:400]))

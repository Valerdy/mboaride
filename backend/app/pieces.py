"""Fichiers des pièces d'agrément : enregistrement, relecture, suppression.

Les fichiers sont rangés sous `config.STOCKAGE/agrement/<id_utilisateur>/`. La base ne garde que
le chemin relatif (`document_agrement.chemin_fichier`). Le type est déduit des premiers octets,
jamais de ce que déclare le client.
"""

from __future__ import annotations

import time
from pathlib import Path

from fastapi import HTTPException

from . import config

TYPES = {
    "jpg": ("image/jpeg", lambda b: b[:3] == b"\xff\xd8\xff"),
    "png": ("image/png", lambda b: b[:8] == b"\x89PNG\r\n\x1a\n"),
    "webp": ("image/webp", lambda b: b[:4] == b"RIFF" and b[8:12] == b"WEBP"),
    "pdf": ("application/pdf", lambda b: b[:5] == b"%PDF-"),
}
MIME = {ext: mime for ext, (mime, _) in TYPES.items()}


def extension(contenu: bytes) -> str:
    """Extension du fichier d'après son contenu, ou 422 si ce n'est ni une image ni un PDF."""
    for ext, (_, reconnu) in TYPES.items():
        if reconnu(contenu):
            return ext
    raise HTTPException(422, "Format non pris en charge : envoyez une photo (JPEG, PNG, WebP) ou un PDF")


def _absolu(chemin: str) -> Path | None:
    racine = config.STOCKAGE.resolve()
    p = (racine / chemin).resolve()
    return p if p.is_relative_to(racine) else None


def enregistrer(id_utilisateur: int, type_document: str, contenu: bytes) -> str:
    """Écrit le fichier et renvoie son chemin relatif (à ranger dans chemin_fichier)."""
    if not contenu:
        raise HTTPException(422, "Aucun fichier reçu : choisissez une photo ou un PDF")
    if len(contenu) > config.TAILLE_MAX_PIECE:
        raise HTTPException(413, f"Fichier trop lourd (maximum {config.TAILLE_MAX_PIECE // (1024 * 1024)} Mo)")
    ext = extension(contenu)
    relatif = f"agrement/{id_utilisateur}/{type_document}-{int(time.time() * 1000)}.{ext}"
    p = config.STOCKAGE / relatif
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(contenu)
    return relatif


def supprimer(chemin: str | None) -> None:
    p = _absolu(chemin) if chemin else None
    if p is not None and p.is_file():
        p.unlink()


def lire(chemin: str | None) -> tuple[bytes, str] | None:
    """Contenu et type MIME, ou None pour une pièce enregistrée avant l'envoi de fichiers."""
    p = _absolu(chemin) if chemin else None
    if p is None or not p.is_file():
        return None
    return p.read_bytes(), MIME.get(p.suffix.lstrip("."), "application/octet-stream")


def description(chemin: str | None) -> dict:
    """Ce que la console doit savoir d'un fichier sans le charger."""
    p = _absolu(chemin) if chemin else None
    if p is None or not p.is_file():
        return {"fichier": False}
    return {"fichier": True, "type_mime": MIME.get(p.suffix.lstrip("."), "application/octet-stream"),
            "taille_octets": p.stat().st_size}

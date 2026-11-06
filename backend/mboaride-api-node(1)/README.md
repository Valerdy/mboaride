# MboaRide API : authentification (Node.js + TypeScript)

Tâche Jira : « API Node.js/TypeScript : authentification SMS/email, hachage des mots de passe, sessions expirantes ».
Stack : Express 5, TypeScript, Knex, **PGlite** (PostgreSQL embarqué en local) / PostgreSQL en production, Argon2id, JWT, Zod, Vitest.
Aucune dépendance à compiler : pas besoin de Visual Studio, de Python ni de Docker pour lancer l'API en local.

## Lancer en local
```bash
npm install
copy .env.example .env      # Windows (macOS/Linux : cp .env.example .env), puis changer SECRET_KEY
npm run dev                 # http://localhost:8000
```
En local, la base est stockée dans le dossier `data/` (créé automatiquement, ignoré par Git).
Avec Docker (API + PostgreSQL) : `docker compose up --build`
Tests : `npm test` · Compilation : `npm run build` puis `npm start`

## Itinéraires et détours (OSRM)
Routes `/routes/route`, `/routes/detour`, `/routes/detours` et `/routes/status`. Installation d'OSRM, scripts Windows et exemples : voir **`docs/OSRM.md`**.
Tests : `npm test` (28 tests : authentification et itinéraires, avec un faux serveur OSRM).

## Si `npm install` échoue sous Windows
- Fermez IntelliJ (il indexe `node_modules` et bloque la suppression des fichiers, d'où les erreurs `EPERM`).
- Supprimez le dossier : `rmdir /s /q node_modules` puis relancez `npm install`.
- Vous pouvez aussi sortir le projet d'un dossier synchronisé ou surveillé (OneDrive, antivirus).

## Parcours (US01)
| Étape | Route | Rôle |
|---|---|---|
| 1 | `POST /auth/register` | Crée le compte (email pro ou téléphone), envoie un code à 6 chiffres |
| 2 | `POST /auth/verify` | Valide le code, renvoie `access_token` + `refresh_token` |
| 2 bis | `POST /auth/otp/resend` | Renvoie un code (l'ancien est invalidé) |
| 3 | `POST /auth/login` | Connexion identifiant + mot de passe |
| 4 | `POST /auth/refresh` | Renouvelle la session (jeton à usage unique) |
| 5 | `POST /auth/logout` | Révoque le jeton de rafraîchissement |
| | `GET /auth/me` | Profil (en-tête `Authorization: Bearer <access_token>`) |
| | `GET /health` | État du service |

Corps JSON en `snake_case` (`full_name`, `access_token`, `refresh_token`). Erreurs au format `{ "detail": "..." }`.

```bash
curl -X POST localhost:8000/auth/register -H "Content-Type: application/json" \
  -d '{"identifier":"prenom.nom@entreprise.cm","password":"Motdepasse123","full_name":"Prénom Nom"}'
# le code s'affiche dans la console du serveur en développement
curl -X POST localhost:8000/auth/verify -H "Content-Type: application/json" \
  -d '{"identifier":"prenom.nom@entreprise.cm","code":"123456"}'
```

## Sécurité mise en place
- Mots de passe hachés avec **Argon2id**, 8 caractères minimum.
- Code de vérification : 6 chiffres aléatoires, valable **5 minutes**, **5 tentatives** maximum, stocké sous forme d'empreinte.
- Session : jeton d'accès JWT de **15 minutes** ; jeton de rafraîchissement de **7 jours**, stocké sous forme d'empreinte, **à usage unique** (rotation). Si un ancien jeton est rejoué, toutes les sessions de l'utilisateur sont coupées.
- Même message d'erreur pour « compte inconnu » et « mauvais mot de passe ».
- Limitation de débit : 100 requêtes par 15 minutes et par adresse sur `/auth` (réglable avec `RATE_LIMIT_MAX`).
- Numéros normalisés au format international (`677123456` devient `+237677123456`).
- Un email dont le domaine correspond à une entreprise partenaire rattache l'utilisateur à son cercle.

## À faire avant la démo / la production
- Brancher un vrai fournisseur SMS/email dans `src/notifications.ts` (aujourd'hui : affichage console).
- Mettre un `SECRET_KEY` long et secret ; restreindre `CORS_ORIGIN` à l'adresse du front.
- Remplacer la création automatique des tables (`src/db.ts`) par des migrations versionnées.
- Créer les entreprises partenaires (table `companies`) pour le rattachement automatique.

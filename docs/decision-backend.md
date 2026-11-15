# Décision : quel backend pour la démonstration ?

> **Statut** : à trancher par le groupe, idéalement avant le 16 novembre au soir (fin du sprint 3 le 20 novembre).
> **Proposé par** : NGAPEPOUE Karl · **Concerne** : Cindy (API Node, application Flutter), Wilfried (API FastAPI, console web), Valerdy (déploiement), Karl (moteur d'agents)

## Pourquoi il faut trancher maintenant

Le dépôt contient aujourd'hui **deux API** qui avancent en parallèle :

- l'**API Node** de Cindy (`backend/mboaride-api-node(1)`, PR #9 et #11), utilisée par l'application Flutter ;
- l'**API FastAPI** de Wilfried (`backend/app`, PR #13 à #19), utilisée par la console web de démonstration.

Chacune a sa propre base de données (deux tables d'utilisateurs, de demandes, d'équipages) et **aucune ne forme les équipages avec le moteur multi-agents**, alors que c'est ce que la grille évalue : convergence en moins de 2 s, moins de 20 messages par équipage, mêmes résultats à chaque exécution, mémoire stable. Le moteur atteint ces cibles sur les cinq scénarios (voir `docs/architecture-multi-agents.md`, section 7), mais la démonstration ne passera pas par lui tant que ce choix n'est pas fait.

## État des lieux (lu dans le code des branches)

| | API Node (Cindy) | API FastAPI (Wilfried) |
|---|---|---|
| Authentification (US01) | réelle : code par SMS ou email, mots de passe hachés (Argon2), jetons de session renouvelables ; 28 tests (authentification et itinéraires) | simplifiée : l'interface envoie l'identifiant de l'utilisateur dans un en-tête, sans vérification |
| Demande de trajet (US04), carte de l'équipage (US08), temps réel | oui ; l'application Flutter est branchée dessus | non |
| Préférences (US02), prix avant confirmation (US09), Mobile Money (US10) | non | oui |
| Console entreprise (US13, US14), scénarios de démo (SR-47) | non | oui, avec une interface web et un lanceur |
| Formation des équipages | regroupement par distance et horaire en TypeScript (`agents.engine.ts`), sans négociation | règles refaites dans l'API (prix et détour des agents, mais pas la négociation ni le score) |
| Base de données | ses propres tables (Knex, PGlite en local) | son propre schéma PostgreSQL (356 lignes) |
| Volume | environ 740 lignes de code serveur (hors `agents.engine.ts` et ses routes) | environ 1 650 lignes de code serveur et 560 lignes de tests, hors interface web |

## Les options

### A. Une seule API, en Python (FastAPI) — recommandation technique

L'API appelle directement le moteur d'agents, dans le même programme.

- **À faire** : porter en Python l'authentification de Cindy, le client OSRM et le temps réel (environ 580 lignes, plus leurs tests) ; faire passer la demande, le choix en mode manuel, l'annulation et la réaffectation par le moteur (la logique est déjà écrite dans la PR #20) ; garder un seul schéma de base ; rebrancher les 5 fichiers de l'application Flutter qui appellent l'API.
- **Avantages** : un seul langage avec le moteur, une seule base, une seule CI, un seul service à déployer ; aucun appel réseau ni copie d'état entre l'API et le moteur ; conforme au dossier de conception (FastAPI, PostgreSQL).
- **Risques** : le portage de l'authentification doit être terminé et testé à temps ; l'application Flutter doit suivre les nouvelles routes.

### B. Une seule API, en Node

- **À faire** : porter en TypeScript les fonctionnalités de Wilfried (préférences, prix, paiement, console, scénarios : environ 1 650 lignes, plus 560 lignes de tests) ; appeler le moteur par le service agents (PR #20), qui reste un second serveur.
- **Avantages** : l'authentification et l'application Flutter ne bougent pas.
- **Risques** : le plus gros volume à réécrire avant la soutenance ; deux programmes à déployer de toute façon (API Node et service agents) ; écart avec le dossier de conception à justifier.

### C. Deux API, un seul moteur — compromis lié au délai

On garde les deux API avec des rôles séparés, et les deux passent par le service agents (PR #20) pour former les équipages.

- **À faire** : `agents.engine.ts` appelle `POST /negotiations` au lieu de regrouper lui-même ; la sélection des offres et l'annulation de l'API FastAPI appellent le service ; déployer trois services (API Node, API FastAPI, service agents).
- **Avantages** : le moins de code à réécrire ; chacun garde son travail.
- **Risques** : deux bases d'utilisateurs (un compte créé dans l'application mobile n'existe pas dans la console web) ; trois services à faire tourner le jour de la soutenance ; l'authentification de la console reste simplifiée.

## Recommandation

**Techniquement : l'option A.** Le cœur évalué est en Python ; une seule API dans ce langage supprime l'interface réseau, la double base de données et un déploiement, qui sont les principales sources de panne le jour de la démonstration. Le vrai atout de la pile Node est l'authentification de Cindy, pas Node lui-même : elle se porte en Python avec les mêmes bibliothèques (Argon2, JWT).

**Si le groupe juge le délai trop court pour A : l'option C**, à condition de présenter clairement au jury deux interfaces (application mobile et console web) qui s'appuient sur le même moteur.

**Dans tous les cas**, la formation des équipages, les offres, le mode manuel, l'annulation et la réaffectation doivent passer par le moteur d'agents : c'est ce que mesure la grille et ce que le jury verra dans le banc.

## Répartition proposée, selon l'option retenue

| | Option A | Option B | Option C |
|---|---|---|---|
| Karl | intégrer le moteur dans l'API (routes de la PR #20), brancher prix, offres et annulation sur le moteur | maintenir le service agents (PR #20), aider au branchement Node | maintenir le service agents (PR #20), aider les deux branchements |
| Cindy | porter l'authentification (US01) et OSRM en Python, rebrancher l'application Flutter | brancher `agents.engine.ts` sur le service agents | brancher `agents.engine.ts` sur le service agents |
| Wilfried | schéma de base unique, remplacer l'en-tête d'identification par le jeton de session | porter préférences, prix, paiement et console en TypeScript | faire appeler le service agents par les offres et l'annulation |
| Valerdy | déployer une API et PostgreSQL (SR-22) | déployer l'API Node, le service agents et PostgreSQL | déployer trois services et deux bases |

## Décision

*À compléter une fois le choix fait : option retenue, date, membres présents, et éventuels ajustements de la répartition. Le dossier de conception (section « Choix technologiques ») sera mis à jour en conséquence.*

- Option retenue :
- Date :
- Ajustements :

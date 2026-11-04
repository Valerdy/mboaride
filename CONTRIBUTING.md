# Règles de contribution

## Branches
- `main` : version stable, toujours fonctionnelle. **Aucun push direct.**
- `develop` : intégration du travail en cours.
- Branches de travail créées depuis `develop`, avec le préfixe suivant :
  - `feature/<sujet-court>` : nouvelle fonctionnalité (ex. `feature/negociation-contract-net`)
  - `fix/<sujet-court>` : correction de bug
  - `docs/<sujet-court>` : documentation
  - `chore/<sujet-court>` : configuration, outillage

## Commits
Format : `type: description courte` (au présent, en français).
Types : `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.
Exemple : `feat: ajout de l'agent conducteur`

## Pull Requests
1. Ouvrir la PR vers `develop` (jamais directement vers `main`).
2. Remplir le modèle de PR.
3. **Au moins 1 approbation** d'un autre membre ; l'auteur ne valide pas sa propre PR.
4. Le CI doit être vert (tests passés).
5. Toutes les discussions doivent être résolues avant la fusion.
6. Fusion par **Squash and merge**, puis suppression de la branche.
7. Une PR doit rester petite et ciblée (idéalement moins de 400 lignes).
8. Le chef de projet fusionne `develop` vers `main` à chaque jalon.

## Revue de code
- Répondre à une demande de revue sous 24 h.
- Commenter avec respect : on critique le code, pas la personne.
- Distinguer le bloquant (« à corriger ») du facultatif (« suggestion »).

## Qualité
- Tout code d'agent ou d'API doit avoir au moins un test.
- Les résultats des agents doivent être **reproductibles** (même scénario, même solution).
- Aucun secret (mots de passe, clés API, jetons) dans le dépôt : utiliser `.env`, jamais commité.
- Aucune donnée personnelle réelle dans les jeux de test : données simulées uniquement.

## Issues
Chaque tâche est une issue, assignée à un membre, avec une étiquette (`backend`, `agents`, `frontend`, `docs`, `securite`).

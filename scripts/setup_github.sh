#!/usr/bin/env bash
# Crée le dépôt GitHub, pousse le code, invite l'équipe et protège main/develop.
# Prérequis : GitHub CLI (https://cli.github.com) puis `gh auth login`.
# Remplir les noms d'utilisateur GitHub de chaque membre (pas les emails).
set -euo pipefail

REPO="mboaride"
VISIBILITY="private"   # voir remarque sur les branches protégées dans le README
MEMBERS=(
  "USERNAME_CINDY"
  "USERNAME_KARL"
  "USERNAME_WILFRIED"
)

git init -b main
git add .
git commit -m "chore: initialisation du dépôt MboaRide"
gh repo create "$REPO" --"$VISIBILITY" --source=. --push
git checkout -b develop && git push -u origin develop

OWNER=$(gh api user --jq .login)
for m in "${MEMBERS[@]}"; do
  gh api -X PUT "repos/$OWNER/$REPO/collaborators/$m" -f permission=push
done

for b in main develop; do
  gh api -X PUT "repos/$OWNER/$REPO/branches/$b/protection" --input - << JSON
{
  "required_status_checks": {"strict": true, "contexts": ["backend", "agents"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "restrictions": null
}
JSON
done
gh repo edit --default-branch develop
echo "Terminé. Invitations envoyées : chaque membre doit les accepter par email."

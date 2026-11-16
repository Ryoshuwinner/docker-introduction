#!/usr/bin/env bash
# 06_publish.sh — Étape 5 : Publication GitHub + Docker Hub
# TOKENS attendus en variables d'environnement (jamais en dur dans ce fichier) :
#   DOCKERHUB_TOKEN  — Personal Access Token Docker Hub (scope: read/write)
#   GH_TOKEN         — GitHub PAT (scope: repo) ou utiliser gh auth login
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

# ─────────────────────────────────────────────────────────────────────────────
banner "Étape 5.0 : Vérification — aucun secret dans le dépôt"
cd "$ROOT_DIR"
LEAKS=$(git grep -rIiE "(token|password|secret|api_key|dockerhub_token)" \
  -- ':!scripts/06_publish.sh' ':!commandes.md' ':!README.md' 2>/dev/null || true)
if [ -n "$LEAKS" ]; then
  err "Secrets potentiels détectés :"
  echo "$LEAKS"
  exit 1
else
  ok "Aucun secret détecté dans le dépôt"
fi

# Vérifie que .env n'est pas tracké
if git ls-files --error-unmatch .env 2>/dev/null; then
  err ".env est tracké par git — ajoutez-le à .gitignore et supprimez-le de l'index"
  exit 1
else
  ok ".env non tracké"
fi

# ─────────────────────────────────────────────────────────────────────────────
banner "Étape 5.1 : Initialisation Git + publication GitHub"
cd "$ROOT_DIR"

# Initialise le dépôt si nécessaire
if [ ! -d ".git" ]; then
  git init
  git branch -M main
  ok "Dépôt git initialisé"
fi

# Configure l'identité git si absente
git config user.name  "$(git config --global user.name  2>/dev/null || echo "$GH_USER")"
git config user.email "$(git config --global user.email 2>/dev/null || echo "${GH_USER}@users.noreply.github.com")"

git add .
git status --short | head -20
git commit -m "TP Docker : sécurisation image et conteneur" --allow-empty

# Création du dépôt GitHub si gh est disponible
if command -v gh &>/dev/null; then
  gh auth status 2>&1 | head -3
  gh repo create "${GH_USER}/${REPO}" --public --source=. --remote=origin 2>/dev/null || \
    warn "Le dépôt existe peut-être déjà"
  git remote set-url origin "https://github.com/${GH_USER}/${REPO}.git"
  git push -u origin main
  ok "Dépôt poussé : https://github.com/${GH_USER}/${REPO}"
else
  warn "gh CLI non disponible — push manuel requis :"
  warn "  git remote add origin https://github.com/${GH_USER}/${REPO}.git"
  warn "  git push -u origin main"
fi

# ─────────────────────────────────────────────────────────────────────────────
banner "Étape 5.2 : Authentification Docker Hub"
if [ -z "${DOCKERHUB_TOKEN:-}" ]; then
  warn "DOCKERHUB_TOKEN non défini — docker login interactif requis"
  warn "  export DOCKERHUB_TOKEN=<votre_token>"
  warn "  echo \"\$DOCKERHUB_TOKEN\" | docker login -u \"${DH_USER}\" --password-stdin"
  exit 0
fi
echo "$DOCKERHUB_TOKEN" | docker login -u "$DH_USER" --password-stdin
ok "Connecté à Docker Hub en tant que ${DH_USER}"

# ─────────────────────────────────────────────────────────────────────────────
banner "Étape 5.3 : Tag et push des images"
docker tag "$TAG_INITIAL"  "$TAG_DH_INITIAL"
docker tag "$TAG_SECURE"   "$TAG_DH_SECURE"
docker push "$TAG_DH_INITIAL"
docker push "$TAG_DH_SECURE"
ok "Images publiées :"
ok "  https://hub.docker.com/r/${DH_USER}/quiz-docker"

# ─────────────────────────────────────────────────────────────────────────────
banner "Étape 5.4 : Vérification — pull depuis un état propre"
docker rmi "$TAG_DH_SECURE" 2>/dev/null || true
docker pull "$TAG_DH_SECURE"
ok "Pull réussi — l'image est publiquement accessible"

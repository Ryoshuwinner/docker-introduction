#!/usr/bin/env bash
# 02_build_secure.sh — Mission 2 : Build de l'image durcie
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.1 : Build de l'image sécurisée"
# Le contexte de build est l'app/ mais le Dockerfile est dans secure/.
# nginx.conf doit être dans le contexte : on le copie temporairement dans app/
# (ou on utilise un contexte étendu). On opte pour un répertoire de build dédié.
BUILD_CTX=$(mktemp -d)
cp -r "${APP_DIR}/." "${BUILD_CTX}/"
cp "${ROOT_DIR}/secure/nginx.conf" "${BUILD_CTX}/nginx.conf"
docker build \
  -f "${ROOT_DIR}/secure/Dockerfile" \
  -t "$TAG_SECURE" \
  "${BUILD_CTX}"
rm -rf "${BUILD_CTX}"
ok "Image ${TAG_SECURE} construite"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.2 : Vérification de l'image sécurisée"
docker images "$IMG" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
echo ""
echo "  Nombre de couches réelles :"
docker inspect "$TAG_SECURE" --format '  {{len .RootFS.Layers}} couches'

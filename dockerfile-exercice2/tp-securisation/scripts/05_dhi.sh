#!/usr/bin/env bash
# 05_dhi.sh — Mission 4 : Docker Hardened Image (DHI)
# Compare une image DHI officielle avec notre image sécurisée.
# Les DHI sont disponibles sur Docker Hub sous docker.io/docker/library-*
# ou via le programme Docker Hardened Images (subscription requise).
# Ce script utilise l'image nginx distroless de Chainguard comme équivalent
# public démontrant les mêmes principes (distroless, non-root, signé).
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

mkdir -p "$SCANS_DIR"

# Image DHI publique de référence : Chainguard nginx (distroless, non-root, signé Sigstore)
DHI_IMG="cgr.dev/chainguard/nginx:latest"
TAG_DHI="quiz-docker:dhi"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 4.1 : Pull de l'image DHI (Chainguard nginx distroless)"
docker pull "$DHI_IMG" 2>&1 | tail -5
ok "Image DHI récupérée : ${DHI_IMG}"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 4.2 : Taille et métadonnées de la DHI"
docker images "$DHI_IMG" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
echo ""
echo "  Nombre de couches :"
docker inspect "$DHI_IMG" --format '  {{len .RootFS.Layers}} couches'
echo "  Utilisateur configuré :"
docker inspect "$DHI_IMG" --format '  Config.User : {{.Config.User}}'

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 4.3 : Shell disponible dans la DHI ?"
if docker run --rm --entrypoint sh "$DHI_IMG" -c 'echo shell ok' 2>/dev/null; then
  warn "Shell présent dans la DHI"
else
  ok "Pas de shell dans la DHI (distroless) — attaque par shell impossible"
fi

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 4.4 : Scan CVE de la DHI"
${TRIVY_CMD} image "$DHI_IMG" \
  --severity HIGH,CRITICAL \
  --no-progress \
  2>&1 | tee "${SCANS_DIR}/dhi.txt" | tail -25

${TRIVY_CMD} image "$DHI_IMG" \
  --format json \
  --no-progress \
  --quiet \
  2>/dev/null > "${SCANS_DIR}/dhi.json" || true

ok "Scan sauvegardé dans scans/dhi.txt"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 4.5 : Comparaison taille — initial / secure / dhi"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" \
  | grep -E "REPOSITORY|quiz-docker|chainguard/nginx"

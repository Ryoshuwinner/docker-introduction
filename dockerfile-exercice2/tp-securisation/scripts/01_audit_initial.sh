#!/usr/bin/env bash
# 01_audit_initial.sh — Mission 1 : Audit de l'image initiale
# Idempotent : peut être relancé sans effets de bord.
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

mkdir -p "$SCANS_DIR"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.1 : Build de l'image initiale"
docker build \
  -t "$TAG_INITIAL" \
  -f "${ROOT_DIR}/initial/Dockerfile" \
  "${APP_DIR}"
ok "Image ${TAG_INITIAL} construite"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.2 : Taille et métadonnées"
docker images "$IMG" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.3 : Utilisateur du processus (doit être non-root)"
CID=$(docker run -d --rm -p ${PORT_INITIAL}:8080 --name audit-initial "$TAG_INITIAL")
sleep 1
docker exec audit-initial id
docker exec audit-initial whoami
docker inspect audit-initial --format '  Config.User : {{.Config.User}}'
docker stop audit-initial >/dev/null
ok "Conteneur audit-initial arrêté"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.4 : Test fonctionnel (HTTP 200)"
CID=$(docker run -d --rm -p ${PORT_INITIAL}:8080 --name test-initial "$TAG_INITIAL")
sleep 1
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT_INITIAL}/")
docker stop test-initial >/dev/null
if [ "$STATUS" = "200" ]; then
  ok "HTTP ${STATUS} — l'application répond correctement"
else
  err "HTTP ${STATUS} — réponse inattendue"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.5 : Couches de l'image (docker history)"
docker history "$TAG_INITIAL" | head -15

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 1.6 : Scan CVE — résumé par sévérité"
${TRIVY_CMD} image "$TAG_INITIAL" \
  --severity HIGH,CRITICAL \
  --no-progress \
  2>&1 | tee "${SCANS_DIR}/initial.txt" | tail -30

# Format JSON pour la comparaison automatique
${TRIVY_CMD} image "$TAG_INITIAL" \
  --format json \
  --no-progress \
  --quiet \
  2>/dev/null > "${SCANS_DIR}/initial.json" || true

ok "Scan sauvegardé dans scans/initial.txt et scans/initial.json"

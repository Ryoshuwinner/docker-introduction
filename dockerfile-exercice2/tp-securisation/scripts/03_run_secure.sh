#!/usr/bin/env bash
# 03_run_secure.sh — Mission 2 : Lancer le conteneur sécurisé + preuves de durcissement
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

CTR="quiz-secure"

# Nettoyage idempotent
docker rm -f "$CTR" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.3 : Lancement avec limites de ressources et restrictions"
docker run -d \
  --name "$CTR" \
  -p ${PORT_SECURE}:8080 \
  --memory=64m \
  --cpus=0.5 \
  --pids-limit=50 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /var/cache/nginx:uid=1001,gid=1001,mode=755 \
  --tmpfs /run:uid=1001,gid=1001,mode=755 \
  --tmpfs /tmp \
  --user 1001:1001 \
  "$TAG_SECURE"

sleep 1
ok "Conteneur ${CTR} démarré"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.4 : Test fonctionnel (HTTP 200)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT_SECURE}/")
if [ "$STATUS" = "200" ]; then
  ok "HTTP ${STATUS} — l'application sécurisée répond correctement"
else
  err "HTTP ${STATUS} — réponse inattendue"
fi

echo ""
echo "  En-têtes de sécurité HTTP :"
curl -sI "http://localhost:${PORT_SECURE}/" | grep -E "X-Frame|X-Content|X-XSS|Referrer|Permissions|Server:"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.5 : Utilisateur dans le conteneur"
docker exec "$CTR" id
docker exec "$CTR" whoami

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.6 : Inspection HostConfig (Memory, CapDrop, ReadOnly)"
docker inspect "$CTR" --format \
  '  Memory       : {{.HostConfig.Memory}} octets
  NanoCpus     : {{.HostConfig.NanoCpus}}
  PidsLimit    : {{.HostConfig.PidsLimit}}
  CapDrop      : {{.HostConfig.CapDrop}}
  ReadonlyRootfs: {{.HostConfig.ReadonlyRootfs}}
  SecurityOpt  : {{.HostConfig.SecurityOpt}}'

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.7 : Tentative d'écriture dans le FS (doit échouer)"
if docker exec "$CTR" sh -c 'echo test > /usr/share/nginx/html/hack.txt' 2>&1; then
  err "ÉCRITURE RÉUSSIE — le filesystem n'est pas en lecture seule !"
else
  ok "Écriture refusée — filesystem correctement en lecture seule"
fi

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.8 : Statistiques de ressources"
docker stats --no-stream "$CTR" \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 2.9 : Absence de montage /var/run/docker.sock"
SOCK_MOUNT=$(docker inspect "$CTR" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' \
  | grep "docker.sock" || true)
if [ -z "$SOCK_MOUNT" ]; then
  ok "Aucun montage de /var/run/docker.sock — conforme"
else
  err "ATTENTION : docker.sock monté : ${SOCK_MOUNT}"
fi

docker rm -f "$CTR" >/dev/null
ok "Conteneur ${CTR} arrêté et supprimé"

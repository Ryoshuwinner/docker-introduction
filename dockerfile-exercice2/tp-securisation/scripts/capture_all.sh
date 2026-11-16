#!/usr/bin/env bash
# capture_all.sh — Lance tous les scripts et génère les 14 captures PNG
# Prérequis : les images quiz-docker:initial et quiz-docker:secure doivent exister.
#   Si non, lancer d'abord : bash scripts/01_audit_initial.sh && bash scripts/02_build_secure.sh
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

CAP="${SCRIPT_DIR}/capture.sh"
mkdir -p "$SCREENSHOTS_DIR" "$SCANS_DIR"

# Garantit que les images existent
if ! docker image inspect "$TAG_INITIAL" &>/dev/null; then
  banner "Build des images manquantes"
  bash "${SCRIPT_DIR}/01_audit_initial.sh"
  bash "${SCRIPT_DIR}/02_build_secure.sh"
fi

# ── 01 : Build initial ───────────────────────────────────────────────────────
bash "$CAP" "01_build_initial" \
  "docker build -t ${TAG_INITIAL} -f ${ROOT_DIR}/initial/Dockerfile ${APP_DIR} 2>&1 | tail -15"

# ── 02 : Utilisateur root ? ──────────────────────────────────────────────────
# Démarre brièvement, capture id, arrête
docker rm -f capctr 2>/dev/null || true
docker run -d --rm --name capctr -p 18080:8080 "$TAG_INITIAL" >/dev/null
sleep 1
bash "$CAP" "02_utilisateur_root" \
  "docker exec capctr id && docker exec capctr whoami && docker inspect capctr --format 'Config.User: {{.Config.User}}'"
docker stop capctr >/dev/null

# ── 03 : Taille + couches ────────────────────────────────────────────────────
bash "$CAP" "03_taille_couches" \
  "docker images ${IMG} --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' && echo '' && docker history ${TAG_INITIAL} | head -15"

# ── 04 : Scan initial ────────────────────────────────────────────────────────
bash "$CAP" "04_scan_initial" \
  "cat ${SCANS_DIR}/initial.txt 2>/dev/null || ${TRIVY_CMD} image ${TAG_INITIAL} --severity HIGH,CRITICAL --no-progress 2>&1 | tail -25"

# ── 05 : App initiale OK ─────────────────────────────────────────────────────
docker rm -f capctr 2>/dev/null || true
docker run -d --rm --name capctr -p 18080:8080 "$TAG_INITIAL" >/dev/null
sleep 1
bash "$CAP" "05_app_initial_ok" \
  "curl -sI http://localhost:18080/ | head -10"
docker stop capctr >/dev/null

# ── 06 : Build sécurisé ──────────────────────────────────────────────────────
bash "${SCRIPT_DIR}/02_build_secure.sh" 2>&1 | tail -20 | tee "${SCREENSHOTS_DIR}/06_build_secure_out.txt"
bash "$CAP" "06_build_secure" "cat '${SCREENSHOTS_DIR}/06_build_secure_out.txt'"

# ── 07 : Run avec limites ────────────────────────────────────────────────────
docker rm -f capsecure 2>/dev/null || true
docker run -d --name capsecure -p 18081:8080 \
  --memory=64m --cpus=0.5 --pids-limit=50 \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /var/cache/nginx:uid=1001,gid=1001,mode=755 \
  --tmpfs /run:uid=1001,gid=1001,mode=755 \
  --tmpfs /tmp \
  "$TAG_SECURE" >/dev/null
sleep 1
bash "$CAP" "07_run_limites" \
  "docker ps --filter name=capsecure --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' && echo '' && curl -sI http://localhost:18081/ | grep -E 'HTTP|X-Frame|X-Content|Server'"

# ── 08 : Inspect privileges ──────────────────────────────────────────────────
bash "$CAP" "08_inspect_privileges" \
  "docker inspect capsecure --format '  Memory       : {{.HostConfig.Memory}} octets\n  NanoCpus     : {{.HostConfig.NanoCpus}}\n  PidsLimit    : {{.HostConfig.PidsLimit}}\n  CapDrop      : {{.HostConfig.CapDrop}}\n  ReadonlyRootfs: {{.HostConfig.ReadonlyRootfs}}\n  SecurityOpt  : {{.HostConfig.SecurityOpt}}'"
docker rm -f capsecure >/dev/null

# ── 09 : Scan sécurisé ───────────────────────────────────────────────────────
bash "$CAP" "09_scan_secure" \
  "cat ${SCANS_DIR}/secure.txt 2>/dev/null || ${TRIVY_CMD} image ${TAG_SECURE} --severity HIGH,CRITICAL --no-progress 2>&1 | tail -20"

# ── 10 : Comparatif tailles ──────────────────────────────────────────────────
bash "$CAP" "10_comparatif_tailles" \
  "docker images ${IMG} --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'"

# ── 11 : DHI scan ────────────────────────────────────────────────────────────
if [ -f "${SCANS_DIR}/dhi.txt" ]; then
  bash "$CAP" "11_dhi_scan" "cat ${SCANS_DIR}/dhi.txt | tail -25"
else
  warn "Scan DHI absent — lancer scripts/05_dhi.sh d'abord"
  echo "⚠ Scan DHI non disponible" > "${SCREENSHOTS_DIR}/11_dhi_scan.txt"
fi

# ── 12–14 : Captures web (manuelles) ─────────────────────────────────────────
banner "Captures 12-14 : manuelles (interfaces web)"
warn "12_push_dockerhub.png   → faire après : bash scripts/06_publish.sh"
warn "13_pull_public.png      → faire après le push, depuis un état docker logout"
warn "14_github_repo.png      → capture navigateur de https://github.com/${GH_USER}/${REPO}"

echo ""
ok "Captures terminées. Fichiers dans : ${SCREENSHOTS_DIR}/"
ls -1 "${SCREENSHOTS_DIR}/"

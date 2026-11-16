#!/usr/bin/env bash
# 04_scan_compare.sh — Mission 3 : Scan sécurisé + tableau comparatif CVE + tailles
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

mkdir -p "$SCANS_DIR"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 3.1 : Scan CVE image sécurisée"
${TRIVY_CMD} image "$TAG_SECURE" \
  --severity HIGH,CRITICAL \
  --no-progress \
  2>&1 | tee "${SCANS_DIR}/secure.txt" | tail -25

${TRIVY_CMD} image "$TAG_SECURE" \
  --format json \
  --no-progress \
  --quiet \
  2>/dev/null > "${SCANS_DIR}/secure.json" || true

ok "Scan sauvegardé dans scans/secure.txt et scans/secure.json"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 3.2 : Tableau comparatif des CVE (généré depuis les JSON)"

count_cve() {
  local file="$1" severity="$2"
  python3 - "$file" "$severity" <<'EOF'
import json, sys
path, sev = sys.argv[1], sys.argv[2].upper()
try:
    data = json.load(open(path))
    results = data.get("Results", [])
    total = sum(
        1 for r in results
        for v in (r.get("Vulnerabilities") or [])
        if v.get("Severity", "").upper() == sev
    )
    print(total)
except Exception:
    print("N/A")
EOF
}

echo ""
printf "  %-15s %10s %10s %10s %10s\n" "Image" "CRITICAL" "HIGH" "MEDIUM" "LOW"
printf "  %-15s %10s %10s %10s %10s\n" "---------------" "--------" "--------" "--------" "--------"

for tag in initial secure; do
  f="${SCANS_DIR}/${tag}.json"
  if [ -f "$f" ]; then
    c=$(count_cve "$f" CRITICAL)
    h=$(count_cve "$f" HIGH)
    m=$(count_cve "$f" MEDIUM)
    l=$(count_cve "$f" LOW)
  else
    c="-"; h="-"; m="-"; l="-"
  fi
  printf "  %-15s %10s %10s %10s %10s\n" "${IMG}:${tag}" "$c" "$h" "$m" "$l"
done
echo ""

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 3.3 : Comparaison des tailles d'images"
docker images "$IMG" \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"

# ─────────────────────────────────────────────────────────────────────────────
banner "Mission 3.4 : Comparaison des couches"
for tag in initial secure; do
  layers=$(docker inspect "${IMG}:${tag}" --format '{{len .RootFS.Layers}}' 2>/dev/null || echo "N/A")
  printf "  %-25s %s couches\n" "${IMG}:${tag}" "$layers"
done

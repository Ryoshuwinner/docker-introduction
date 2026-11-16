#!/usr/bin/env bash
# 00_env.sh — Variables communes à tous les scripts du TP
# Source ce fichier depuis les autres scripts : source "$(dirname "$0")/00_env.sh"
# NE PAS écrire de secrets ici. Les tokens arrivent via variables d'environnement.

# ── Identifiants (sans valeur par défaut pour forcer l'explicite) ───────────
GH_USER="${GH_USER:-lcgregorio93}"
DH_USER="${DH_USER:-lcgregorio93}"

# ── Dépôt et image ──────────────────────────────────────────────────────────
REPO="tp-docker-securisation"
IMG="quiz-docker"

# ── Tags ────────────────────────────────────────────────────────────────────
TAG_INITIAL="${IMG}:initial"
TAG_SECURE="${IMG}:secure"
TAG_DH_INITIAL="${DH_USER}/${IMG}:initial"
TAG_DH_SECURE="${DH_USER}/${IMG}:secure"

# ── Répertoires ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SCANS_DIR="${ROOT_DIR}/scans"
SCREENSHOTS_DIR="${ROOT_DIR}/screenshots"
APP_DIR="${ROOT_DIR}/app"

# ── Scanner CVE ─────────────────────────────────────────────────────────────
# On utilise Trivy via Docker (aucune installation locale requise).
TRIVY_IMG="aquasec/trivy:latest"
TRIVY_CMD="docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ${TRIVY_IMG}"

# ── Port de test ────────────────────────────────────────────────────────────
PORT_INITIAL=8080
PORT_SECURE=8081

# ── Couleurs pour les bannières ──────────────────────────────────────────────
BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${BOLD}  $1${RESET}${CYAN}$(printf '%*s' $((57 - ${#1})) '')║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

ok()   { echo -e "${GREEN}  ✓ $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${RESET}"; }
err()  { echo -e "${RED}  ✗ $*${RESET}"; }

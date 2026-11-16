#!/usr/bin/env bash
# capture.sh <nom_sans_extension> "<commande>"
# Exécute la commande, sauvegarde la sortie en .txt, génère un PNG.
# Chaîne : freeze → termshot → aha+wkhtmltoimage → Pillow (Python)
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <nom> \"<commande>\""
  exit 1
fi

NAME="$1"
CMD="$2"
TXT="${SCREENSHOTS_DIR}/${NAME}.txt"
PNG="${SCREENSHOTS_DIR}/${NAME}.png"

mkdir -p "$SCREENSHOTS_DIR"

echo -e "${CYAN}  → Capture : ${NAME}${RESET}"
echo -e "${YELLOW}    Commande : ${CMD}${RESET}"

# Exécute et enregistre la sortie (avec couleurs ANSI via script)
eval "$CMD" 2>&1 | tee "$TXT" || true

echo ""

# ── Méthode 1 : freeze (charmbracelet) ──────────────────────────────────────
if command -v freeze &>/dev/null; then
  freeze "$TXT" -o "$PNG" --language ansi --theme dracula --window 2>/dev/null && \
    { ok "PNG généré via freeze : ${PNG}"; exit 0; }
fi

# ── Méthode 2 : termshot ────────────────────────────────────────────────────
if command -v termshot &>/dev/null; then
  termshot --filename "$PNG" -- sh -c "cat '$TXT'" 2>/dev/null && \
    { ok "PNG généré via termshot : ${PNG}"; exit 0; }
fi

# ── Méthode 3 : aha + wkhtmltoimage ─────────────────────────────────────────
if command -v aha &>/dev/null && command -v wkhtmltoimage &>/dev/null; then
  HTML="${TXT%.txt}.html"
  cat "$TXT" | aha --black --title "$NAME" > "$HTML"
  wkhtmltoimage --quiet "$HTML" "$PNG" 2>/dev/null && \
    { ok "PNG généré via aha+wkhtmltoimage : ${PNG}"; exit 0; }
fi

# ── Méthode 4 : Python / Pillow ─────────────────────────────────────────────
python3 - "$TXT" "$PNG" "$NAME" <<'PYEOF'
import sys, re, textwrap
from PIL import Image, ImageDraw, ImageFont

txt_path, png_path, title = sys.argv[1], sys.argv[2], sys.argv[3]

# Nettoie les séquences ANSI
ansi_re = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

with open(txt_path, encoding="utf-8", errors="replace") as f:
    raw = f.read()
clean = ansi_re.sub("", raw)

lines = clean.splitlines()
# Tronque à 40 lignes max pour tenir dans une capture
lines = lines[:40]
# Wrapping sur 100 caractères
wrapped = []
for l in lines:
    wrapped.extend(textwrap.wrap(l, width=100) or [""])

FONT_SIZE = 15
PAD = 20
LINE_H = FONT_SIZE + 4
W = 100 * 9 + PAD * 2          # ~920 px
H = max(len(wrapped), 1) * LINE_H + PAD * 2 + 30

img = Image.new("RGB", (W, H), color=(30, 30, 46))   # fond Dracula
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", FONT_SIZE)
except Exception:
    font = ImageFont.load_default()

# Titre
draw.text((PAD, PAD - 5), f"● {title}", fill=(203, 166, 247), font=font)
# Corps
for i, line in enumerate(wrapped):
    draw.text((PAD, PAD + 25 + i * LINE_H), line, fill=(205, 214, 244), font=font)

img.save(png_path)
print(f"  ✓ PNG généré via Pillow : {png_path}")
PYEOF

ok "PNG généré via Pillow : ${PNG}"

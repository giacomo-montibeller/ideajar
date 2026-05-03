#!/usr/bin/env bash
# Slice 10 — generate the 2 PWA icons.
#
# Re-run when the design changes (color, letter, font). The generated
# PNGs live in priv/static/icons/icon-{192,512}.png and are committed
# to the repo, so this script is for reproducibility only — it is NOT
# wired into mix.exs aliases.
#
# Two backends are supported. The first one available wins:
#
#   1. ImageMagick (`magick` or `convert`) — preferred on CI / Linux
#      with build deps installed. Uses the `-strip` flag so no
#      ancillary chunks (tEXt/iTXt/pHYs) precede IHDR; the test
#      parser's chunk-scan handles either way, but `-strip` keeps
#      the bytes minimal.
#
#   2. Python + Pillow (PIL) — fallback for environments without
#      ImageMagick. Same visual output (solid #2299dd background,
#      bold sans-serif white "I" centered, ~50% vertical occupancy
#      so the maskable safe zone stays satisfied).
#
# Either backend writes "any maskable"-safe icons.

set -euo pipefail

cd "$(dirname "$0")/../.."

SIZES=(192 512)
OUT_DIR="priv/static/icons"
BG="#2299dd"

mkdir -p "$OUT_DIR"

if command -v magick >/dev/null 2>&1; then
  CMD="magick"
elif command -v convert >/dev/null 2>&1; then
  CMD="convert"
else
  CMD=""
fi

if [ -n "$CMD" ]; then
  echo "Using $CMD (ImageMagick)…"
  for size in "${SIZES[@]}"; do
    pointsize=$((size / 2))
    "$CMD" -size "${size}x${size}" "xc:$BG" \
      -strip \
      -font "DejaVu-Sans-Bold" -pointsize "$pointsize" \
      -fill white -gravity center -annotate +0+0 "I" \
      "$OUT_DIR/icon-${size}.png"
  done
elif command -v python3 >/dev/null 2>&1; then
  echo "Using python3 + Pillow…"
  for size in "${SIZES[@]}"; do
    python3 - "$size" "$BG" "$OUT_DIR/icon-${size}.png" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont

size = int(sys.argv[1])
bg = sys.argv[2]
out = sys.argv[3]

img = Image.new("RGB", (size, size), bg)
draw = ImageDraw.Draw(img)

# Try a few common bold sans-serif fonts; fall back to PIL default.
font = None
for path in [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]:
    try:
        font = ImageFont.truetype(path, size // 2)
        break
    except (OSError, IOError):
        continue
if font is None:
    font = ImageFont.load_default()

text = "I"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
# Center the glyph; offset by the bbox origin so glyph descenders/ascenders
# don't bias the centering.
x = (size - tw) // 2 - bbox[0]
y = (size - th) // 2 - bbox[1]

draw.text((x, y), text, fill="white", font=font)
img.save(out, "PNG", optimize=True)
PYEOF
  done
else
  echo "ERROR: neither ImageMagick (magick/convert) nor python3 with Pillow is available." >&2
  exit 1
fi

echo "Generated:"
ls -l "$OUT_DIR"/icon-{192,512}.png

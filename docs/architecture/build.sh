#!/usr/bin/env bash
# Builds docs/architecture/INSPECTO_SYSTEM_ARCHITECTURE.pdf from Markdown and Mermaid sources.
# Requirements: pandoc >= 3, Node.js >= 20, `npm install` in this directory (mermaid-cli, puppeteer).
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")"

BIN="./node_modules/.bin"
MMDC="${MMDC:-$BIN/mmdc}"
PUPPETEER_CFG="$(mktemp)"
trap 'rm -f "$PUPPETEER_CFG"' EXIT
echo '{"args":["--no-sandbox"]}' > "$PUPPETEER_CFG"

echo "1/3 Rendering diagrams"
mkdir -p out
for src in diagrams/*.mmd; do
  name="$(basename "$src" .mmd)"
  "$MMDC" -q -i "$src" -o "out/$name.svg" -c diagrams/mermaid-config.json -p "$PUPPETEER_CFG" -b white
done

echo "2/3 Building HTML"
pandoc INSPECTO_SYSTEM_ARCHITECTURE.md \
  --from markdown+pipe_tables+header_attributes \
  --to html5 --standalone --embed-resources \
  --toc --toc-depth=2 --number-sections \
  --metadata lang=ru \
  --css style.css --include-before-body title.html \
  --variable pagetitle="Inspecto — архитектура" \
  --template template.html \
  -o out/architecture.html

echo "3/3 Rendering PDF"
node render-pdf.mjs out/architecture.html INSPECTO_SYSTEM_ARCHITECTURE.pdf
echo "Done: $(pwd)/INSPECTO_SYSTEM_ARCHITECTURE.pdf"

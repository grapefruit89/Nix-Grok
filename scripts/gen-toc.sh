#!/usr/bin/env bash
# Generates docs/TOC.md — anchor index of all headings across docs/ for LLM navigation.
# Re-run after any docs change: sudo bash /etc/nixos/scripts/gen-toc.sh

set -eu

NIXOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="$NIXOS_DIR/docs"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

cat >> "$TMPFILE" << 'HEADER'
---
meta:
  role: toc
  generated: true
  purpose: Globales Inhaltsverzeichnis aller Heading-Anker aus docs/ für KI-Navigation
---

# Globales Inhaltsverzeichnis — /etc/nixos/docs

> **Automatisch generiert** — nicht manuell bearbeiten.
> Neu generieren: `sudo bash /etc/nixos/scripts/gen-toc.sh`
>
> **Für KIs:** Dieses Verzeichnis listet alle Anker aller Dokumente in docs/.
> Suche einen Abschnitt hier → navigiere direkt per Anker ohne jede Datei zu lesen.

HEADER

while IFS= read -r file; do
  rel="${file#"$DOCS_DIR/"}"
  if [ "$rel" = "TOC.md" ]; then continue; fi

  printf '\n## %s\n\n' "$rel" >> "$TMPFILE"

  gawk -v rel="$rel" '
    /^#{2,4} / {
      n = 0
      while (substr($0, n+1, 1) == "#") n++
      text = substr($0, n+2)

      # Extract explicit {#anchor} or generate from text
      anchor = ""
      if (match(text, /\{#[^}]+\}/)) {
        anchor = substr(text, RSTART+2, RLENGTH-3)
      } else {
        anchor = tolower(text)
        gsub(/ /, "-", anchor)
        gsub(/[^a-z0-9_-]/, "", anchor)
      }

      display = text
      sub(/ \{#[^}]+\}$/, "", display)

      indent = ""
      for (i = 2; i < n; i++) indent = indent "  "

      printf "%s- [`#%s`](%s#%s) \342\200\224 %s\n", indent, anchor, rel, anchor, display
    }
  ' "$file" >> "$TMPFILE"
done < <(find "$DOCS_DIR" -name "*.md" -xtype f | sort)

install -m 0644 "$TMPFILE" "$DOCS_DIR/TOC.md"
echo "TOC.md generiert: $DOCS_DIR/TOC.md ($(wc -l < "$DOCS_DIR/TOC.md") Zeilen)"

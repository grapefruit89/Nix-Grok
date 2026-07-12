#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Live-USB Ein-Kommando-Kaltstart q958 — gleiche Config, ohne Secrets (CasaOS-Stil)
#   docs:
#     - docs/guides/GUIDE-cold-start.md
#     - docs/EMERGENCY-RECOVERY.md
#   tags:
#     - cold-start
#     - disko
#     - bootstrap
# ---
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/grapefruit89/Nix-Grok.git}"
BRANCH="${BRANCH:-main}"
MNT="/mnt"
ROOT="${MNT}/etc/nixos"

usage() {
  cat <<EOF
cold-start-q958 — Neuinstallation vom Live-USB (ohne Secrets)

Usage:
  cold-start-q958.sh          # disko + nixos-install (Default)
  cold-start-q958.sh help

Voraussetzung: NixOS Minimal ISO, Netzwerk.
Secrets: automatisch aus profile.local.nix.example (Platzhalter).
         Externe Secrets nach erstem Boot via secrets-portal setzen.

One-liner:
  curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/main/scripts/cold-start-q958.sh | sudo bash

Recovery (bestehende Platte retten): emergency-bootstrap-q958.sh recover
EOF
}

abort_if_live_root() {
  if findmnt -rn / -o SOURCE 2>/dev/null | grep -qE '/dev/sd|/dev/nvme'; then
    echo "FEHLER: Von installiertem System gebootet — bitte NixOS Live-USB starten!" >&2
    exit 1
  fi
}

clone_repo() {
  mkdir -p "${MNT}"
  if [[ -d "${ROOT}/.git" ]] && [[ -f "${ROOT}/flake.nix" ]]; then
    echo "Repo bereits unter ${ROOT}"
    return 0
  fi
  echo "Klone ${REPO_URL} (Branch: ${BRANCH})…"
  git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${ROOT}"
}

ensure_profile_local() {
  local dest="${ROOT}/machines/q958/profile.local.nix"
  local example="${ROOT}/machines/q958/profile.local.nix.example"
  if [[ -f /media/moritz/profile.local.nix ]]; then
    cp /media/moritz/profile.local.nix "${dest}"
    echo "profile.local.nix von USB übernommen"
  elif [[ -f "${dest}" ]]; then
    echo "profile.local.nix bereits vorhanden"
  elif [[ -f "${example}" ]]; then
    cp "${example}" "${dest}"
    echo "profile.local.nix aus .example erstellt (CHANGE_ME-Platzhalter)"
    echo "  → Interne *arr-Keys werden beim Boot auto-generiert"
    echo "  → Externe Secrets (CF, Usenet, VPN, …) via secrets-portal nach Boot"
  else
    echo "FEHLER: weder profile.local.nix noch .example gefunden" >&2
    exit 1
  fi
}

do_cold_start() {
  abort_if_live_root
  clone_repo
  ensure_profile_local
  echo "=== disko: Tier-A partitionieren ==="
  "${ROOT}/scripts/disko-q958.sh" install
  echo "=== nixos-install ==="
  nixos-install --flake "${ROOT}#q958" --impure --no-root-passwd
  cat <<'POST'

=== Kaltstart fertig — reboot ===

Nach dem Boot:
  1. SSH oder Konsole — System läuft mit Platzhalter-Secrets (Dev-Mode)
  2. https://secrets.<deine-domain> — externe Secrets setzen (Cloudflare, Usenet, VPN, …)
  3. sudo nixos-rebuild-safe.sh switch (Mensch) nach Portal-Einträgen

Interne API-Keys (*arr, Jellyseerr, …) brauchst du nicht manuell — media-secrets.nix erzeugt sie.

Recovery statt Neuinstall? → emergency-bootstrap-q958.sh recover
POST
}

case "${1:-start}" in
  start | "") do_cold_start ;;
  help | -h | --help) usage ;;
  *) usage; exit 1 ;;
esac
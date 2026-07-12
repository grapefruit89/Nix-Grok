#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Prüft ob q958 auf disko-Tier-A-Layout läuft (vor Löschen von Legacy-Code)
#   docs:
#     - machines/q958/disko-deprecations.json
#   tags:
#     - disko
#     - verify
# ---
set -euo pipefail

ROOT="/etc/nixos"
PROFILE="${ROOT}/machines/q958/profile.nix"
MANIFEST="${ROOT}/machines/q958/disko-deprecations.json"
DEVICE=""
DISKO_MANAGED="false"
FAIL=0

log_ok() { echo "OK  $*"; }
log_fail() { echo "FAIL $*"; FAIL=1; }
log_warn() { echo "WARN $*"; }

# device aus profile.nix (einfacher Parser)
if [[ -f "$PROFILE" ]]; then
  DEVICE=$(grep -E 'device = "/dev/' "$PROFILE" | head -1 | sed -n 's/.*device = "\([^"]*\)".*/\1/p' || true)
  if grep -qE 'diskoManaged = true' "$PROFILE"; then
    DISKO_MANAGED="true"
  fi
fi

echo "=== disko-verify-active (q958) ==="
echo "device: ${DEVICE:-unbekannt}"
echo "profile diskoManaged: ${DISKO_MANAGED}"

# 1) FS-Labels (disko setzt diese bei frischer Installation)
for want in NIXBOOT NIXPERSIST; do
  if lsblk -o LABEL -nr 2>/dev/null | grep -qx "$want"; then
    log_ok "FS-Label $want vorhanden"
  else
    log_fail "FS-Label $want fehlt"
  fi
done

# 2) GPT-Partlabels disko-Schema: disk-tierA-<name>
for want in disk-tierA-NIXBOOT disk-tierA-NIXPERSIST; do
  if lsblk -o PARTLABEL -nr "${DEVICE:-/dev/sda}" 2>/dev/null | grep -qx "$want"; then
    log_ok "GPT-Partlabel $want (disko-Schema)"
  else
    log_warn "GPT-Partlabel $want fehlt — Legacy-Platte (BOOT/NIXHOME_PERSIST)? disko-Reinstall ausstehend"
  fi
done

# 3) profile-Flag (menschliche Bestätigung nach Reinstall)
if [[ "$DISKO_MANAGED" == "true" ]]; then
  log_ok "profile.nix: diskoManaged = true"
else
  log_fail "profile.nix: diskoManaged noch false — nach Reinstall auf true setzen"
fi

# 4) flake: disko-enabled.nix vorhanden
if [[ -f "${ROOT}/machines/q958/disko-enabled.nix" ]]; then
  log_ok "disko-enabled.nix vorhanden"
else
  log_fail "disko-enabled.nix fehlt"
fi

# 5) Eval: disko-Modul aktiv wenn diskoManaged
if [[ "$DISKO_MANAGED" == "true" ]]; then
  if nix eval --impure "${ROOT}#nixosConfigurations.q958.config.fileSystems.\"/\".device" 2>/dev/null | grep -q partlabel; then
    log_ok "NixOS fileSystems.\"/\" nutzt disko partlabel"
  elif nix eval --impure "${ROOT}#nixosConfigurations.q958.config.fileSystems.\"/\".device" 2>/dev/null | grep -q NIXPERSIST; then
    log_warn "fileSystems.\"/\" noch by-label — disko-Modul im flake aktivieren?"
  else
    log_fail "fileSystems.\"/\" nicht evaluierbar"
  fi
fi

echo "=== Ergebnis: $([[ $FAIL -eq 0 ]] && echo BESTANDEN || echo NICHT BEREIT FÜR PRUNE) ==="
exit "$FAIL"
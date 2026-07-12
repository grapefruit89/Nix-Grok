# shellcheck shell=bash
# Shared guard: block destructive disko on q958 live root (tier-A).
# Sourced by /etc/nixos/scripts/nix and profile.d.

nix_disko_guard_profile() {
  printf '%s\n' /etc/nixos/machines/q958/profile.nix
}

nix_disko_guard_tier_a_device() {
  local profile dev
  profile="$(nix_disko_guard_profile)"
  if [[ -f "$profile" ]]; then
    dev="$(grep -E 'device(ById)?\s*=' "$profile" 2>/dev/null | head -1 \
      | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
    if [[ -n "$dev" ]]; then
      printf '%s\n' "$dev"
      return 0
    fi
  fi
  printf '%s\n' /dev/sda
}

# True when this machine runs from tier-A (live q958) — not Live-USB installer.
nix_disko_guard_live_system() {
  local marker dev root_src
  marker=/etc/nixos/machines/q958/.live-system-no-destructive-disko
  [[ -f "$marker" ]] || return 1
  dev="$(nix_disko_guard_tier_a_device)"
  root_src="$(findmnt -rn / -o SOURCE 2>/dev/null || true)"
  [[ -n "$root_src" && "$root_src" == "${dev}"* ]]
}

# True when nix argv must be blocked on live system.
nix_disko_guard_should_block() {
  local joined="$*"
  # Unrelated to disko
  [[ "$joined" != *disko* ]] && return 1
  # Safe preview
  [[ "$joined" == *--dry-run* ]] && return 1
  # The accident command and variants
  [[ "$joined" == *" script"* ]] && return 0
  [[ "$joined" == *" -- script"* ]] && return 0
  # Destructive modes
  [[ "$joined" == *destroy* ]] && return 0
  [[ "$joined" == *"format,mount"* ]] && return 0
  [[ "$joined" == *"--mode format"* ]] && return 0
  [[ "$joined" == *"--mode mount"* ]] && return 0
  [[ "$joined" == *"--mode disko"* ]] && return 0
  # Any direct nix-community/disko run without dry-run
  if [[ "$joined" == *"nix-community/disko"* ]] || [[ "$joined" == *"github:nix-community/disko"* ]]; then
    return 0
  fi
  return 1
}

nix_disko_guard_block_message() {
  cat >&2 <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║ BLOCKED — destruktives disko auf LIVE q958 verboten              ║
╠══════════════════════════════════════════════════════════════════╣
║ Der Befehl „nix run … disko -- script“ hat am 2026-07-12         ║
║ ESP + ext4-Superblock zerstört. Store war noch rettbar.          ║
║                                                                  ║
║ Sicher (nur Anzeige):  disko-plan   (= disko-q958.sh plan)       ║
║ Lernen:                disko-vm                                    ║
║ Recovery (Live-USB):   emergency-bootstrap-q958.sh recover       ║
║ Neuinstall (Live-USB): cold-start-q958.sh                        ║
║                                                                  ║
║ Doku: docs/EMERGENCY-RECOVERY.md                                 ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}
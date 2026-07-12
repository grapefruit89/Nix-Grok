#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Agent-sichere Nix-Abfragen (Shell/MCP) — kein TUI, kein LSP
#   docs:
#     - CLAUDE.md
#     - AGENTS.md
#   tags:
#     - agents
#     - nix
#     - manix
# ---
set -euo pipefail

ROOT="/etc/nixos"
FLAKE="${ROOT}#nixosConfigurations.q958"
CONFIG="${FLAKE}.config"

usage() {
  cat <<'EOF'
nix-agent-query — Nix-Abfragen für KI-Agenten (Grok, Claude, Antigravity)

Agent-Entscheidungsbaum:
  Repo-Wissen (ADRs, Module, error_pattern)  → nixos-docs MCP
  nixpkgs-Pakete / upstream NixOS-Optionen     → nixos MCP (oder: options)
  lib.* / builtins                             → nixos MCP Noogle (oder: noogle-search)
  Tatsächlicher Wert auf q958 (evaluiert)      → config <attr>
  nixpkgs-Options-Doku (Shell-Fallback)        → options <query>

Usage:
  nix-agent-query.sh options [--source nixos_options] <query>
  nix-agent-query.sh config <attrpath>     # z.B. services.openssh.enable
  nix-agent-query.sh help

Beispiele:
  nix-agent-query.sh options services.openssh
  nix-agent-query.sh options --source hm_options programs.git.enable
  nix-agent-query.sh config my.rollout.stufe
  nix-agent-query.sh config services.caddy.enable
EOF
}

run_nix_eval() {
  local attr="$1"
  if [[ -w "$ROOT" ]] || [[ "$(stat -c '%U' "$ROOT" 2>/dev/null || echo root)" == "$(id -un)" ]]; then
    nix eval --impure --json "${CONFIG}.${attr}"
  else
    sudo nix eval --impure --json "${CONFIG}.${attr}"
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  options | opt)
    exec manix "$@"
    ;;
  config | cfg)
    attr="${1:-}"
    if [[ -z "$attr" ]]; then
      echo "error: attrpath fehlt (z.B. services.openssh.enable)" >&2
      exit 1
    fi
    run_nix_eval "$attr"
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    echo "error: unbekannter Befehl: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
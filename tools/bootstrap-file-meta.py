#!/usr/bin/env python3
"""Setzt standardisierte File-Meta-Header (zero Nix cost). Idempotent."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ENTRIES: list[dict] = json.loads(r"""
[
  {"path": "flake.nix", "layer": 1, "role": "flake", "purpose": "Flake-Inputs und NixOS-Output q958 inkl. Pakete", "tags": ["flake", "entrypoint"]},
  {"path": "configuration.nix", "layer": 2, "role": "machine", "purpose": "Legacy-Einstieg — importiert machines/q958/default.nix", "tags": ["entrypoint", "q958"]},
  {"path": "lib/caddy-helpers.nix", "layer": 5, "role": "lib", "purpose": "Caddy vHost-Helfer — Proxy, SSO, Unix-Socket-Upstreams", "tags": ["caddy", "ingress"]},
  {"path": "lib/caddy-snippets.nix", "layer": 5, "role": "lib", "purpose": "Gemeinsame Caddyfile-Snippets — SSO, Security-Header, Tailscale", "tags": ["caddy", "snippets"]},
  {"path": "lib/critical-systemd.nix", "layer": 5, "role": "lib", "purpose": "Restart=always, StartLimit=0, OOM-Score für kritische Infrastruktur", "docs": ["docs/AUDIT-blocky-caddy-ipv6.md"], "tags": ["systemd", "critical"]},
  {"path": "lib/dev-secrets.nix", "layer": 5, "role": "lib", "purpose": "Development-Warnungen für Platzhalter-Secrets", "tags": ["secrets", "dev"]},
  {"path": "lib/dns-policy.nix", "layer": 5, "role": "lib", "purpose": "DNS-Upstream-Verschlüsselungs-Assertions (DoT/DoH)", "docs": ["docs/adr/001-dns-dot-fail-closed.md", "docs/AUDIT-blocky-caddy-ipv6.md"], "tags": ["dns", "dot"]},
  {"path": "lib/kernel/blacklist-filesystems.nix", "layer": 5, "role": "lib", "purpose": "Kernel-Blacklist Schicht A — exotische Dateisysteme", "tags": ["kernel", "blacklist"]},
  {"path": "lib/kernel/blacklist-global.nix", "layer": 5, "role": "lib", "purpose": "Kernel-Blacklist global — Datacenter/Legacy/Sicherheit", "tags": ["kernel", "blacklist"]},
  {"path": "lib/kernel/blacklist-homelab-headless.nix", "layer": 5, "role": "lib", "purpose": "Kernel-Blacklist headless — WLAN, Audio, Desktop", "tags": ["kernel", "blacklist", "headless"]},
  {"path": "lib/kernel/policy.nix", "layer": 5, "role": "lib", "purpose": "Kernel-Slim-Zwiebelschale — Whitelist/Blacklist + Assertions", "tags": ["kernel", "policy"]},
  {"path": "lib/kernel/whitelist-homelab.nix", "layer": 5, "role": "lib", "purpose": "Kernel-Whitelist Homelab-Hardware 2010–2025", "tags": ["kernel", "whitelist"]},
  {"path": "lib/memory-policy.nix", "layer": 5, "role": "lib", "purpose": "systemd MemoryMax/MemoryHigh und OOMScoreAdjust pro Dienst-Tier", "docs": ["docs/adr/003-oom-cgroup-isolation.md", "docs/memory_oom.md"], "tags": ["oom", "systemd"]},
  {"path": "lib/nftables-rules.nix", "layer": 5, "role": "lib", "purpose": "nftables ruleset Generator — WAN-Härtung, skuid, portscan", "docs": ["docs/adr/008-nftables-l4-hardening.md", "docs/guides/GUIDE-nftables-hardening.md"], "tags": ["nftables", "firewall"]},
  {"path": "lib/uid-registry.nix", "layer": 5, "role": "lib", "purpose": "Statische UID/GID-Registry für skuid und Reproduzierbarkeit", "tags": ["uid", "security"]},
  {"path": "lib/gatus-endpoints.nix", "layer": 5, "role": "lib", "purpose": "Gatus-Endpoint-Generator aus Service-Spec", "tags": ["gatus", "observability"]},
  {"path": "lib/rollout.nix", "layer": 5, "role": "lib", "purpose": "Rollout-Helfer erstAb für stufenweise Service-Aktivierung", "tags": ["rollout"]},
  {"path": "lib/unix-sockets.nix", "layer": 5, "role": "lib", "purpose": "Standard-UDS-Pfade und Caddy-Upstream-Konvertierung", "tags": ["unix-socket", "caddy"]},
  {"path": "lib/vpn-killswitch.nix", "layer": 5, "role": "lib", "purpose": "VPN-Kill-Switch systemd-Attrs für privado WireGuard", "tags": ["vpn", "privado"]},
  {"path": "machines/q958/access.nix", "layer": 2, "role": "machine", "purpose": "Stufe 0+ Zugang — Notfall-User, LAN, DNS/IPv6-Assertions", "docs": ["docs/adr/001-dns-dot-fail-closed.md", "docs/adr/002-ipv6-homelab-v4-only.md"], "tags": ["access", "rollout"]},
  {"path": "machines/q958/boot-baseline.nix", "layer": 2, "role": "machine", "purpose": "Feste systemd-boot-Baseline-Generationen 85/86", "tags": ["boot", "baseline"]},
  {"path": "machines/q958/default.nix", "layer": 2, "role": "machine", "purpose": "q958-Verdrahtung — Module-Imports und my.configs ohne .enable", "tags": ["wiring", "q958"]},
  {"path": "machines/q958/dev-mode.nix", "layer": 2, "role": "machine", "purpose": "nixos-rebuild Dev-Mode-Warnung für Platzhalter-Secrets", "tags": ["dev", "secrets"]},
  {"path": "machines/q958/hardware.nix", "layer": 2, "role": "machine", "purpose": "Boot/Root-FS und Kernel-Module an Tier-A aus profile.nix", "tags": ["hardware", "tier-a"]},
  {"path": "machines/q958/kernel-slim.nix", "layer": 2, "role": "machine", "purpose": "Host-spezifische Kernel-Slim-Policy für q958", "lib": ["lib/kernel/policy.nix"], "tags": ["kernel-slim"]},
  {"path": "machines/q958/network.nix", "layer": 2, "role": "machine", "purpose": "Verdrahtung Netzwerk — Blocky, Tailscale, Pocket-ID, Privado", "docs": ["docs/AUDIT-blocky-caddy-ipv6.md"], "services": ["blocky", "tailscale", "pocket-id"], "tags": ["network", "dns"]},
  {"path": "machines/q958/profile.local.nix", "layer": 2, "role": "machine", "purpose": "Lokale Secrets und Notfall-Passwort (gitignored)", "tags": ["secrets", "gitignored"]},
  {"path": "machines/q958/profile.nix", "layer": 2, "role": "machine", "purpose": "Einzige Datenquelle aller q958-Maschinenwerte", "docs": ["docs/ROADMAP.md"], "tags": ["profile", "single-source-of-truth"]},
  {"path": "machines/q958/rollout.nix", "layer": 2, "role": "machine", "purpose": "Einzige Quelle für .enable — schrittweise Aktivierung nach rollout.stufe", "docs": ["docs/ROADMAP.md"], "lib": ["lib/rollout.nix"], "tags": ["rollout", "enable"]},
  {"path": "machines/q958/secrets.nix", "layer": 2, "role": "machine", "purpose": "Secret-Provisionierung unter /var/lib/secrets (vor SOPS)", "tags": ["secrets", "provision"]},
  {"path": "machines/q958/storage.nix", "layer": 2, "role": "machine", "purpose": "Storage-Tier-Assertions und Automount-Optionen q958", "tags": ["storage", "tier-policy"]},
  {"path": "modules/00-core.nix", "layer": 3, "role": "module", "purpose": "Boot-Safeguard, Nix-Tuning, ZRAM-Swap, zentrale System-Optionen", "tags": ["core", "zram", "nix"]},
  {"path": "modules/10-network.nix", "layer": 3, "role": "module", "purpose": "Blocky DNS, Valkey, PostgreSQL, Tailscale, Pocket-ID, Privado", "docs": ["docs/adr/001-dns-dot-fail-closed.md", "docs/adr/002-ipv6-homelab-v4-only.md", "docs/AUDIT-blocky-caddy-ipv6.md"], "lib": ["lib/dns-policy.nix", "lib/memory-policy.nix", "lib/critical-systemd.nix"], "services": ["blocky", "postgresql", "redis-valkey", "tailscaled", "pocket-id"], "tags": ["dns", "network", "database"]},
  {"path": "modules/05-alerting.nix", "layer": 3, "role": "module", "purpose": "SRE webhook/ntfy alerts for VPN and backup failures", "docs": ["docs/guides/GUIDE-nftables-hardening.md"], "tags": ["alerting", "sre"]},
  {"path": "modules/15-firewall.nix", "layer": 3, "role": "module", "purpose": "nftables L4 — checkRuleset, WAN-Härtung, skuid, CrowdSec/Fail2ban", "docs": ["docs/adr/008-nftables-l4-hardening.md", "docs/guides/GUIDE-nftables-hardening.md"], "lib": ["lib/nftables-rules.nix"], "services": ["nftables"], "tags": ["firewall", "nftables"]},
  {"path": "modules/20-security.nix", "layer": 3, "role": "module", "purpose": "Sovereign-Unlock, SSH-Härtung, Fail2ban, Dropbear-Rescue", "docs": ["docs/SECURITY.md"], "services": ["sshd", "fail2ban"], "tags": ["security", "ssh"]},
  {"path": "modules/25-kernel-policy.nix", "layer": 3, "role": "module", "purpose": "NixOS-Optionen Kernel-Slim-Modus und Homelab-Profil", "lib": ["lib/kernel/policy.nix"], "tags": ["kernel", "options"]},
  {"path": "modules/30-storage.nix", "layer": 3, "role": "module", "purpose": "Impermanence, MergerFS, Restic, Storage-Mover zwischen Tiers", "services": ["restic-backup"], "tags": ["storage", "impermanence"]},
  {"path": "modules/35-automount.nix", "layer": 3, "role": "module", "purpose": "Label-Automount Tier A/B/C und optional MergerFS", "services": ["storage-automount"], "tags": ["automount", "storage"]},
  {"path": "modules/40-observability.nix", "layer": 3, "role": "module", "purpose": "Gatus, Vector/Loki/Grafana, CrowdSec", "docs": ["docs/AUDIT-blocky-caddy-ipv6.md", "docs/memory_oom.md"], "lib": ["lib/memory-policy.nix"], "services": ["gatus", "loki", "grafana", "vector", "crowdsec"], "tags": ["observability"]},
  {"path": "modules/50-media/arr-helper.nix", "layer": 3, "role": "module", "purpose": "Fabrik für *arr-Apps — User, systemd, Caddy, RAM-Limits", "docs": ["docs/memory_oom.md"], "lib": ["lib/memory-policy.nix"], "services": ["sonarr", "radarr", "readarr", "prowlarr"], "tags": ["media", "arr"]},
  {"path": "modules/50-media/sonarr-radarr.nix", "layer": 3, "role": "module", "purpose": "Sonarr + Radarr — gemeinsame dendritische Datei", "docs": ["docs/adr/007-dendritic-one-file-per-service.md", "docs/guides/GUIDE-dendritic-architecture.md"], "services": ["sonarr", "radarr"], "tags": ["media", "arr", "dendritic"]},
  {"path": "modules/50-media/readarr.nix", "layer": 3, "role": "module", "purpose": "Readarr — eigene dendritische Datei", "docs": ["docs/adr/007-dendritic-one-file-per-service.md"], "services": ["readarr"], "tags": ["media", "arr", "dendritic"]},
  {"path": "modules/50-media/prowlarr.nix", "layer": 3, "role": "module", "purpose": "Prowlarr — VPN-NetNS, eigene dendritische Datei", "docs": ["docs/adr/007-dendritic-one-file-per-service.md"], "services": ["prowlarr"], "tags": ["media", "arr", "dendritic", "vpn"]},
  {"path": "modules/50-media/default.nix", "layer": 3, "role": "module", "purpose": "Media-Domain — Submodule-Aggregation und Enable-Optionen", "tags": ["media", "imports"]},
  {"path": "modules/50-media/jellyfin.nix", "layer": 3, "role": "module", "purpose": "Jellyfin QuickSync + Jellyseerr hinter Caddy", "docs": ["docs/memory_oom.md"], "lib": ["lib/memory-policy.nix"], "services": ["jellyfin", "seerr"], "tags": ["media", "jellyfin"]},
  {"path": "modules/50-media/sabnzbd.nix", "layer": 3, "role": "module", "purpose": "SABnzbd Usenet mit VPN-Kill-Switch", "docs": ["docs/memory_oom.md"], "lib": ["lib/memory-policy.nix", "lib/vpn-killswitch.nix"], "services": ["sabnzbd"], "tags": ["media", "usenet"]},
  {"path": "modules/50-media/sync.nix", "layer": 3, "role": "module", "purpose": "Media-Stack Locale/Config-Sync per systemd oneshot", "services": ["media-stack-config-sync"], "tags": ["media", "sync"]},
  {"path": "modules/60-apps/automation.nix", "layer": 3, "role": "module", "purpose": "Paperless-ngx und n8n Workflow-Automatisierung", "docs": ["docs/memory_oom.md"], "lib": ["lib/memory-policy.nix"], "services": ["paperless-web", "n8n"], "tags": ["automation"]},
  {"path": "modules/60-apps/core.nix", "layer": 3, "role": "module", "purpose": "Vaultwarden, Homepage, Filebrowser, Linkwarden, Open WebUI", "services": ["vaultwarden", "homepage"], "tags": ["apps"]},
  {"path": "modules/60-apps/default.nix", "layer": 3, "role": "module", "purpose": "Apps-Domain — Submodule, Caddy-Ingress-Härtung", "lib": ["lib/critical-systemd.nix", "lib/memory-policy.nix"], "services": ["caddy"], "tags": ["apps", "caddy"]},
  {"path": "modules/60-apps/grok.nix", "layer": 3, "role": "module", "purpose": "Grok Build CLI als systemd-Dienst (Headless-Dev)", "services": ["grok"], "tags": ["grok", "headless-dev"]},
  {"path": "modules/60-apps/hermes.nix", "layer": 3, "role": "module", "purpose": "Hermes-Agent Gateway mit Container-Isolation", "services": ["hermes-agent"], "tags": ["hermes", "llm"]},
  {"path": "modules/60-apps/iot.nix", "layer": 3, "role": "module", "purpose": "Home Assistant und Zigbee-Stack (Mosquitto, Zigbee2MQTT)", "docs": ["docs/memory_oom.md"], "services": ["home-assistant", "mosquitto", "zigbee2mqtt"], "tags": ["iot"]},
  {"path": "modules/70-forge.nix", "layer": 3, "role": "module", "purpose": "Forgejo Git, Semaphore Ansible-UI, Cockpit", "lib": ["lib/unix-sockets.nix"], "services": ["forgejo", "semaphore"], "tags": ["forge", "git"]},
  {"path": "modules/80-gaming.nix", "layer": 3, "role": "module", "purpose": "AMP Game-Server-Manager in FHS-Sandbox", "services": ["amp"], "tags": ["gaming", "amp"]},
  {"path": "modules/90-policy.nix", "layer": 3, "role": "module", "purpose": "Bubblewrap-Policies für jailed LLM-Coding-Agenten", "services": ["jailed-agents"], "tags": ["policy", "sandbox"]},
  {"path": "packages/grok-cli/default.nix", "role": "package", "purpose": "Gepinnte xAI Grok Build CLI als Nix-Derivation", "tags": ["grok", "package"]},
  {"path": "packages/nixos-docs-mcp/default.nix", "role": "package", "purpose": "DuckDB MCP-Server für lokale nixos_docs.db", "tags": ["mcp", "nixos-docs"]},
  {"path": "users/moritz/default.nix", "layer": 4, "role": "user", "purpose": "System-User moritz aus profile.nix", "tags": ["user", "moritz"]},
  {"path": "users/moritz/home.nix", "layer": 4, "role": "user", "purpose": "Home-Manager — Grok CLI, MCP, Dotfiles", "tags": ["home-manager", "grok", "mcp"]},
  {"path": "users/moritz/preferences.nix", "layer": 4, "role": "user", "purpose": "Locale, Zeitzone, Sprache für moritz", "tags": ["locale"]},
  {"path": "users/moritz/profile.nix", "layer": 4, "role": "user", "purpose": "Einzige Datenquelle moritz-spezifischer Werte (Keys, Domain)", "tags": ["profile", "moritz"]}
]
""")

MD_ENTRIES: list[dict] = [
    {"path": "AGENTS.md", "role": "doc", "purpose": "Projektregeln — 5-Schichten-Architektur, q958, Rollout, harte Regeln", "docs": ["docs/FILE-META.md"], "tags": ["agents", "architecture"]},
    {"path": "README.md", "role": "doc", "purpose": "Repo-Einstieg — Schnellstart q958, Flake-Build", "docs": ["AGENTS.md", "docs/ROADMAP.md"], "tags": ["readme"]},
    {"path": "claudereview_prompt.md", "role": "doc", "purpose": "Idempotenter Repo-Review-Prompt für Claude", "tags": ["review", "prompt"]},
    {"path": "docs/SECURITY.md", "role": "doc", "purpose": "Secrets-Hygiene — was nicht ins Git, profile.local, SOPS", "tags": ["security", "secrets"]},
    {"path": "docs/ROADMAP.md", "role": "doc", "purpose": "Rollout-Stufen und Feature-Roadmap q958", "tags": ["roadmap", "rollout"]},
    {"path": "docs/SESSION-2026-06-17-review-fixes.md", "role": "doc", "purpose": "Session-Log Review-Fixes 2026-06-17", "tags": ["session", "changelog"]},
    {"path": "docs/migration-from-chats.md", "role": "doc", "purpose": "Migrationsnotizen aus Chat-Verlauf", "tags": ["migration", "notes"]},
    {"path": "docs/unraid-migration-map.md", "role": "doc", "purpose": "Mapping Unraid → NixOS Dienste und Pfade", "tags": ["migration", "unraid"]},
    {"path": "docs/FILE-META.md", "role": "doc", "purpose": "Spezifikation File-Meta-Header und Index-Tooling", "docs": ["meta/schema.yaml"], "tags": ["meta", "llm"]},
    {"path": "docs/AUDIT-blocky-caddy-ipv6.md", "role": "doc", "purpose": "Audit DNS, Blocky, Caddy, IPv6, RAM-Tiers q958", "docs": ["docs/memory_oom.md"], "tags": ["audit", "dns", "ipv6"]},
    {"path": "docs/memory_oom.md", "role": "doc", "purpose": "RAM/OOM-Policy — cgroup-Limits und Tier-Modell", "docs": ["docs/adr/003-oom-cgroup-isolation.md"], "lib": ["lib/memory-policy.nix"], "tags": ["oom", "systemd"]},
    {"path": "docs/adr/README.md", "role": "doc", "purpose": "ADR-Index — alle Architecture Decision Records", "tags": ["adr", "index"]},
    {"path": "docs/adr/001-dns-dot-fail-closed.md", "role": "doc", "purpose": "ADR-001 DNS-over-TLS, Blocky-only, fail-closed", "docs": ["docs/adr/README.md"], "tags": ["adr", "dns"]},
    {"path": "docs/adr/002-ipv6-homelab-v4-only.md", "role": "doc", "purpose": "ADR-002 IPv6 Homelab v4-only auf eno1", "docs": ["docs/adr/README.md"], "tags": ["adr", "ipv6"]},
    {"path": "docs/adr/003-oom-cgroup-isolation.md", "role": "doc", "purpose": "ADR-003 RAM-Isolation per systemd cgroup", "docs": ["docs/adr/README.md"], "tags": ["adr", "oom"]},
    {"path": "docs/adr/004-unix-socket-upstreams.md", "role": "doc", "purpose": "ADR-004 Unix-Socket-Upstreams für Caddy", "docs": ["docs/adr/README.md"], "tags": ["adr", "caddy"]},
    {"path": "docs/adr/005-critical-systemd-restart.md", "role": "doc", "purpose": "ADR-005 Restart=always für kritische Dienste", "docs": ["docs/adr/README.md"], "tags": ["adr", "systemd"]},
    {"path": "docs/adr/006-sops-migration-path.md", "role": "doc", "purpose": "ADR-006 SOPS-Migration vs. secrets-provision", "docs": ["docs/adr/README.md"], "tags": ["adr", "sops"]},
    {"path": "docs/adr/007-dendritic-one-file-per-service.md", "role": "doc", "purpose": "ADR-007 Dendritische Module — eine Datei pro Dienst", "docs": ["docs/adr/README.md", "docs/guides/GUIDE-dendritic-architecture.md"], "tags": ["adr", "dendritic"]},
    {"path": "docs/adr/008-nftables-l4-hardening.md", "role": "doc", "purpose": "ADR-008 nftables L4-Härtung (KB-Synthese)", "docs": ["docs/adr/README.md", "docs/guides/GUIDE-nftables-hardening.md"], "lib": ["lib/nftables-rules.nix"], "tags": ["adr", "nftables"]},
    {"path": "docs/guides/GUIDE-dendritic-architecture.md", "role": "doc", "purpose": "Guide — dendritische Modul-Architektur", "docs": ["docs/adr/007-dendritic-one-file-per-service.md", "AGENTS.md"], "tags": ["guide", "dendritic"]},
    {"path": "docs/guides/GUIDE-nftables-hardening.md", "role": "doc", "purpose": "Guide — nftables L4-Härtung für Homelab q958", "docs": ["docs/adr/008-nftables-l4-hardening.md"], "tags": ["guide", "nftables"]},
]

PURPOSE_RE = re.compile(
    r"^# =+\s*\n# PURPOSE\s*\n# =+\s*\n(?:# .*\n)*",
    re.MULTILINE,
)


def nix_header(entry: dict) -> str:
    lines = ["# ---", "# meta:"]
    if "layer" in entry:
        lines.append(f"#   layer: {entry['layer']}")
    lines.append(f"#   role: {entry['role']}")
    lines.append(f"#   purpose: {entry['purpose']}")
    for key in ("docs", "lib", "services", "tags"):
        if entry.get(key):
            lines.append(f"#   {key}:")
            for item in entry[key]:
                lines.append(f"#     - {item}")
    lines.append("# ---")
    return "\n".join(lines) + "\n"


def md_header(entry: dict) -> str:
    lines = ["---", "meta:"]
    lines.append(f"  role: {entry['role']}")
    lines.append(f"  purpose: {entry['purpose']}")
    for key in ("docs", "lib", "services", "tags"):
        if entry.get(key):
            lines.append(f"  {key}:")
            for item in entry[key]:
                lines.append(f"    - {item}")
    lines.append("---")
    return "\n".join(lines) + "\n\n"


def strip_nix_preamble(text: str) -> str:
    text = text.lstrip("\n")
    if text.startswith("# ---\n"):
        m = re.match(r"^# ---\n# meta:\n(?:# .*\n)*# ---\n", text)
        if m:
            text = text[m.end() :]
    text = PURPOSE_RE.sub("", text)
    lines = text.splitlines(keepends=True)
    while lines and lines[0].startswith("#"):
        lines.pop(0)
    return "".join(lines).lstrip("\n")


def strip_md_preamble(text: str) -> str:
    if text.startswith("---\n"):
        m = re.match(r"^---\nmeta:\n(?:  .*\n)*---\n*", text)
        if m:
            return text[m.end() :]
    return text


def apply(path: Path, header: str, strip) -> bool:
    body = strip(path.read_text(encoding="utf-8"))
    new = header + body
    old = path.read_text(encoding="utf-8")
    if old != new:
        path.write_text(new, encoding="utf-8")
        return True
    return False


def main() -> int:
    changed: list[str] = []
    skip_dirs = {".git", "stage-nixos", ".grok", ".cache"}
    nix_paths = {
        p.relative_to(ROOT).as_posix()
        for p in ROOT.rglob("*.nix")
        if not skip_dirs.intersection(p.parts)
    }
    entry_paths = {e["path"] for e in ENTRIES}
    missing_meta = sorted(nix_paths - entry_paths)
    if missing_meta:
        print("WARN: .nix ohne Meta-Eintrag:", file=sys.stderr)
        for m in missing_meta:
            print(f"  {m}", file=sys.stderr)

    for entry in ENTRIES:
        path = ROOT / entry["path"]
        if not path.exists():
            print(f"skip missing {entry['path']}", file=sys.stderr)
            continue
        if apply(path, nix_header(entry), strip_nix_preamble):
            changed.append(entry["path"])

    for entry in MD_ENTRIES:
        path = ROOT / entry["path"]
        if apply(path, md_header(entry), strip_md_preamble):
            changed.append(entry["path"])

    print(f"Changed {len(changed)} files")
    for c in changed:
        print(f"  {c}")
    return 1 if missing_meta else 0


if __name__ == "__main__":
    sys.exit(main())
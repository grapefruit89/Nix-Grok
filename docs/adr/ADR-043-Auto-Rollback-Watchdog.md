# ADR-043: Auto-Rollback Watchdog & Caddy API

## Status
**Accepted**

## Kontext
NixOS bietet durch sein deklaratives Modell die Fähigkeit, Rollbacks durchzuführen. Standardmäßig prüft NixOS beim Booten, ob alle erforderlichen systemd-Dienste fehlerfrei gestartet (`active`) sind. 
Ein gravierendes Problem ("Silent Failure") tritt auf, wenn ein Dienst zwar startet, aber logisch defekt ist (z.B. Caddy startet, kann aber keine Konfiguration laden und wirft einen 502-Fehler, oder verweilt dauerhaft im `failed` Status nach einem Neustart-Versuch). Wenn in so einem Zustand ein Update eingespielt wird, merkt der Admin das bei Headless-Servern oft erst zu spät.

Zudem wird eine dynamische API für den Caddy-Proxy benötigt, um ohne Nix-Rebuild kurzfristig IP-Sperren oder Rate-Limits anwenden zu können.

## Entscheidung

### 1. Flugschreiber Watchdog (`boot-watchdog.service`)
Wir etablieren einen aktiven System-Watchdog, der zu drei Zeitpunkten anläuft:
- `2 Minuten` nach dem Boot
- `30 Minuten` nach dem Boot
- `60 Minuten` nach dem Boot

**Logik:**
- Der Watchdog überprüft kritische Kernfunktionen (primär den Caddy-Proxy).
- **Auto-Rollback:** Wenn der Watchdog innerhalb der ersten 15 Minuten (`Uptime < 900s`) einen gravierenden Ausfall detektiert, löst er gnadenlos und vollautomatisch ein `nixos-rebuild boot --rollback` aus und zwingt den Server zum Reboot. 
- **Graceful Logging:** Schlägt der Check nach 30 oder 60 Minuten fehl (Uptime > 15m), wird *kein* Reboot ausgelöst. Dies verhindert katastrophale Rebootschleifen, falls der Administrator den Dienst manuell gestoppt hat, um Wartungsarbeiten durchzuführen.

### 2. Caddy Admin API
Die Caddy API wird lokal auf `127.0.0.1:2020` (`caddyAdmin` Port) gebunden. Dies passt strikt in unsere `20xx` Security-Taxonomie. 
- Niemals darf die API öffentlich erreichbar sein.
- Keine abweichenden Port-Formate (wie 2019) sind gestattet.

## Konsequenzen
- Defekte Nix-Updates, die den Reverse-Proxy lahmlegen, werden nach 2 Minuten automatisch ungeschehen gemacht.
- Der Server repariert sich selbst.
- Es gibt keine unbeabsichtigten Reboots bei manuellen Wartungsarbeiten am laufenden Server.

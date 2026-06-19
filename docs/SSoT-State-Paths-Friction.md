# SSoT /var/lib Friction Point

Gemäß der GEMINI.md Architektur-Regel müssen alle relationalen Datenbanken und State-Dateien aus Performance- und Integritätsgründen auf /data/state/ (Tier A SSD) mit POSIX Locks liegen.

## Betroffene Apps (Stand: 19.06.2026)
Bei der Analyse der Nix-Module unter modules/60-apps/, modules/40-observability.nix und modules/50-media/ wurde festgestellt, dass folgende Apps noch auf dem generischen /var/lib/ Pfad liegen und umgezogen werden müssen:

- Home Assistant (/var/lib/hass)
- Zigbee2mqtt (/var/lib/zigbee2mqtt)
- Mosquitto (/var/lib/mosquitto)
- n8n (/var/lib/n8n)
- Paperless (/var/lib/paperless)
- Linkwarden (/var/lib/linkwarden)
- Loki (/var/lib/loki)
- Grafana (/var/lib/grafana)
- Caddy (/var/lib/caddy)
- Gatus (/var/lib/gatus)
- Crowdsec (/var/lib/crowdsec)
- Forgejo (/var/lib/forgejo)
- Semaphore (/var/lib/semaphore)
- Vaultwarden (/var/lib/vaultwarden)
- Hermes (/var/lib/hermes)

## Migration
Alle oben genannten Pfade müssen in ihren jeweiligen Modulen manuell durch /data/state/<appname> ersetzt werden, andernfalls verletzen sie die SSoT-Compliance und es können Inkonsistenzen bei Snapshots und Tiered-Storage Moves auftreten.

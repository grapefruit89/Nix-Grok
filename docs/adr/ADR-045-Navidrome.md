---
domain: 50-media
id: ADR-045
status: accepted
provides: [music-streaming]
requires: [zfs-storage]
---

# ADR 045: Einführung von Navidrome

## Kontext
Für das Streaming von Musik wurde eine leichtgewichtige, kompatible Lösung gesucht.

## Entscheidung
Navidrome wird als primärer Musik-Streaming-Server eingesetzt. Er ist in Go geschrieben, sehr ressourcenschonend und vollständig Subsonic-API kompatibel.

## Konsequenzen
*   Dienst wird auf Port 5100 bereitgestellt.
*   Zentrale Einbindung in die Stealth-Landingpage.

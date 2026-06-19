---
domain: 60-apps
id: ADR-044
status: accepted
provides: [stealth-routing, bot-protection, obfuscation]
requires: [caddy, javascript-frontend]
---

# ADR 044: True Stealth POST-Knocking für Landingpage

## Kontext
Die Stealth-Landingpage (`nix.m7c5.de`) enthielt zunächst Base64-codierte vollqualifizierte Subdomains (`jellyfin.nix.m7c5.de`) im Frontend-HTML und in den Javascript-Click-Handlern. Dies war unsicher ("Taschenspielertricks"), da jeder einfache Crawler Base64 decodieren und die verborgenen Backend-Subdomains auslesen konnte.

## Entscheidung
Wir setzen **Event-Driven POST-Knocking** ein, um Links (`<a href>`) und Klartext/Base64-Ziele restlos aus dem Frontend zu eliminieren.

1.  **Frontend (Javascript):** Klicks werden auf `.card`-DIVs abgefangen. Es wird explizit `e.isTrusted` geprüft, um echte menschliche Hardware-Eingaben von simulierten Bot-Klicks (`.click()`) zu unterscheiden.
2.  **Dynamische Form-Injektion:** Nur bei validem Klick erzeugt das Javascript ein unsichtbares `<form method="POST" action="/go/X">` und feuert dieses ab.
3.  **Backend (Caddy):** Caddy lauscht exklusiv auf `POST`-Requests für den Pfad `/go/*`. Erhält Caddy diesen Request, antwortet es mit einem `303 See Other` HTTP-Redirect auf die tatsächliche Subdomain (z.B. `jellyfin.nix.m7c5.de`).

## Konsequenzen
*   **Positiv:** Absolute Unsichtbarkeit für Crawler. Quelltext-Analysen (statisch wie dynamisch) zeigen keine Subdomains mehr auf.
*   **Negativ:** Javascript ist zwingend erforderlich, um die Landingpage zu bedienen.

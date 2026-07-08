# lib/assertions.nix — Strukturierte NixOS-Assertions mit ADR-Referenzen
#
# Zweck: Maschinenlesbare Fehlermeldungen bei nixos-rebuild, die KI und Mensch
# direkt sagen was kaputt ist, warum die Regel existiert, und wie man es behebt.
#
# Verwendung:
#   let asserts = import ../../lib/assertions.nix { inherit lib; };
#   in assertions = [ (asserts.mkAssert { code = ...; ... }) ];
{ lib }:
{
  # mkAssert erzeugt eine NixOS-Assertion mit strukturierter Fehlermeldung.
  # Felder:
  #   code      — Fehlercode (z.B. "DNS-001"), erscheint in der ersten Zeile
  #   was       — Was ist das Problem? (kurz, 1 Zeile)
  #   warum     — Warum gibt es diese Regel? (ADR-Referenz, Invariante)
  #   beheben   — Wie beheben? (konkreter Nix-Ausdruck oder Schritt)
  #   umgehung  — Ausweg wenn Beheben nicht geht (optional, nur für DEV-/Übergangsszenarien)
  #   assertion — Der zu prüfende Boolean-Ausdruck
  mkAssert =
    {
      code,
      was,
      warum,
      beheben,
      umgehung ? null,
      assertion,
    }:
    {
      inherit assertion;
      message = lib.concatStringsSep "\n" (
        [
          "[${code}] ${was}"
          "  Warum:   ${warum}"
          "  Beheben: ${beheben}"
        ]
        ++ lib.optional (umgehung != null) "  Umgehung: ${umgehung}"
      );
    };
}

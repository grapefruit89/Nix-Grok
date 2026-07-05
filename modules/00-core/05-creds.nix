{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.creds;

  # Leeres Flag-Argument wenn kein TPM — kein doppeltes Leerzeichen im Befehl
  tpmFlag = lib.optionalString cfg.useTpm "--with-key=tpm2";

  sealExample =
    name:
    "printf '%s' 'WERT' | systemd-creds encrypt ${tpmFlag} --name=${name} - ${cfg.storeDir}/${name}.cred";
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.creds = {
    enable = lib.mkEnableOption "systemd-creds Credential-Store (Production ab Stufe 9)";

    useTpm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        TPM2 für Credential-Sealing nutzen.
        false (default) = host key (/var/lib/systemd/credential.secret, Disk-gebunden).
        true            = TPM-gesiegelt (physisch gebunden, Diebstahlschutz).
        Migration: nur diesen Wert ändern → Credentials neu versiegeln → rebuild.
      '';
    };

    storeDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/credstore.encrypted";
      description = "Verzeichnis für versiegelte .cred-Dateien.";
    };

    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Erwartete Credential-Namen — fehlendes .cred gibt Warnung bei Aktivierung.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # Immer aktiv: sops-nix ist für q958 explizit verboten
    {
      assertions = [
        {
          assertion = !(config.sops.enable or false);
          message = ''
            ANTIPATTERN: sops-nix ist für q958 (single-host, rotierbare Keys) verboten.
            Nutze my.creds (systemd-creds) stattdessen.
            Begründung: docs/guides/ANTIPATTERNS.md#sops-nix
            ADR:        docs/adr/024-systemd-creds-tpm.md
          '';
        }
      ];
    }

    (lib.mkIf cfg.enable {
      # Credential-Store-Verzeichnis anlegen
      systemd.tmpfiles.rules = [
        "d ${cfg.storeDir} 0700 root root -"
      ];

      # Prüfe bei Aktivierung ob alle deklarierten Credentials versiegelt vorliegen
      system.activationScripts.credentialCheck = {
        text = ''
          echo "=== systemd-creds Check (${if cfg.useTpm then "TPM2" else "host key"}) ==="
          _missing=0
          ${lib.concatMapStringsSep "\n" (name: ''
            if [ ! -f "${cfg.storeDir}/${name}.cred" ]; then
              echo "  FEHLT:  ${cfg.storeDir}/${name}.cred"
              echo "  Siegel: ${sealExample name}"
              _missing=1
            fi
          '') cfg.keys}
          if [ "$_missing" -eq 1 ]; then
            echo "  Fehlende Credentials versiegeln, dann rebuild."
          else
            echo "  Alle Credentials vorhanden (${lib.optionalString cfg.useTpm "TPM2-gesiegelt"})."
          fi
        '';
        deps = [ ];
      };

      # tpm2-tss-Pakete nur wenn TPM aktiv
      environment.systemPackages = lib.optionals cfg.useTpm [
        pkgs.tpm2-tss
        pkgs.tpm2-tools
      ];
    })
  ];
}

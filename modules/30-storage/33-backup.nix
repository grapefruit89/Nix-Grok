# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Restic offsite S3 backup + MEGA secondary backup (Vaultwarden + Secrets)
#   docs:
#     - docs/guides/GUIDE-data-management.md
#   services:
#     - restic-backup
#   tags:
#     - storage
#     - backup
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgImp = config.my.impermanence;
  cfgBackup = config.my.services.restic-backup;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.restic-backup = {
    enable = lib.mkEnableOption "Restic offsite S3 backup schedule";
    healthcheckUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dead Man's Switch heartbeat URL.";
    };
    secondaryEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "MEGA-Sekundärbackup (rclone) — nur Vaultwarden + Secrets. Credentials: /var/lib/secrets/restic_mega_creds";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── RESTIC ENCRYPTED CLOUD SYNC ───────────────────────────────────────────
    (lib.mkIf cfgBackup.enable {
      services.restic.backups.tier-a-sovereign = {
        initialize = true;
        passwordFile = "/var/lib/secrets/restic_password";
        environmentFile = "/var/lib/secrets/restic_s3_creds";

        # Backup-Philosophie (ADR-023): nur unwiederbringliche Daten.
        # Medien (Tier C), Thumbnails, Caches → kein Backup (re-downloadbar / re-generierbar).
        # /etc/nixos → kein Backup (steht auf GitHub, redundant und S3-teuer).
        paths = [
          # ── Kritische Secrets ─────────────────────────────────────────────
          "${cfgImp.persistMountPoint}/var/lib/secrets"

          # ── Datenbanken (nicht re-generierbar) ───────────────────────────
          "${cfgImp.persistMountPoint}/var/lib/postgresql"
          "${cfgImp.persistMountPoint}/var/lib/vaultwarden"
          "${cfgImp.persistMountPoint}/var/lib/pocket-id"
          "${cfgImp.persistMountPoint}/var/lib/linkwarden"

          # ── Dokumente (Paperless-NGX — absolut unwiederbringlich) ────────
          "${cfgImp.persistMountPoint}/var/lib/paperless"

          # ── Smart-Home-State ──────────────────────────────────────────────
          "${cfgImp.persistMountPoint}/var/lib/hass"
          "${cfgImp.persistMountPoint}/var/lib/zigbee2mqtt"

          # ── Nutzerdaten (Fortschritt, Lesezeichen) ────────────────────────
          "${cfgImp.persistMountPoint}/var/lib/audiobookshelf"

          # ── Netzwerk-Konfiguration (nicht deklarativ in NixOS-Modul) ─────
          "${cfgImp.persistMountPoint}/var/lib/technitium-dns-server"

          # ── Observability-Dashboards ──────────────────────────────────────
          "${cfgImp.persistMountPoint}/var/lib/grafana"

          # ── Immich (Placeholder — Originale NICHT hier, nur DB via postgresql) ──
          # Wenn Immich kommt: Fotos zu groß für Free-S3 → Originale auf ext. HDD
          # Immich-DB läuft über postgresql (bereits oben), keine extra Pfade nötig.
        ];

        exclude = [
          # ── Regenerierbare Medien-Metadaten ───────────────────────────────
          "**/MediaCover"
          "**/thumbnails/**"
          "**/Thumbnails/**"
          # Paperless: Thumbnails und Preview-Bilder sind regenerierbar
          "**/paperless/media/documents/thumbnails/**"
          "**/paperless/media/documents/archive/**"

          # ── Caches & temporäre Daten ──────────────────────────────────────
          "**/Backups"
          "**/cache/**"
          "**/Cache/**"
          "**/logs/**"
          "**/*.log"
          "/mnt/fast_pool/cache"
          "/var/cache/jellyfin"

          # ── Regenerierbare Indizes (Paperless Volltext-Suche) ─────────────
          "**/paperless/data/media/**"
          "**/whoosh/**"
        ];

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
        ];

        # Services stoppen um Write-Drift während des Backups zu vermeiden.
        # Reihenfolge: Apps zuerst, dann Datenbanken.
        backupPrepareCommand = ''
          echo "Stopping services for consistent backup snapshot..."
          systemctl stop \
            paperless-web paperless-scheduler paperless-task-queue \
            home-assistant linkwarden vaultwarden zigbee2mqtt \
            audiobookshelf technitium-dns-server || true
          systemctl stop mosquitto postgresql || true
        '';

        # Services nach Backup wieder starten (auch bei Fehler).
        backupCleanupCommand = ''
          echo "Restarting services after backup..."
          systemctl start postgresql mosquitto || true
          systemctl start \
            paperless-web paperless-scheduler paperless-task-queue \
            home-assistant linkwarden vaultwarden zigbee2mqtt \
            audiobookshelf technitium-dns-server || true
        '';
      };

      systemd.services.restic-backups-tier-a-sovereign = {
        postStop = lib.mkIf (cfgBackup.healthcheckUrl != "") ''
          status=$(${pkgs.systemd}/bin/systemctl show -p ExecMainStatus --value restic-backups-tier-a-sovereign.service 2>/dev/null || echo 1)
          if [ "$status" = "0" ]; then
            ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 "${cfgBackup.healthcheckUrl}"
          else
            ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 "${cfgBackup.healthcheckUrl}/fail" || true
          fi
        '';
      };
    })

    # ── MEGA-SEKUNDÄRBACKUP (Vaultwarden + Secrets) ───────────────────────────
    # Zweites Ziel für die kritischsten Daten — client-side verschlüsselt via MEGA.
    # Credentials: /var/lib/secrets/restic_mega_creds (RCLONE_CONFIG_MEGA_*)
    # Frequenz: wöchentlich (Sonntag 04:00) um MEGA-Bandbreite zu schonen.
    (lib.mkIf (cfgBackup.enable && cfgBackup.secondaryEnable) {
      services.restic.backups.tier-a-mega = {
        initialize = true;
        repository = "rclone:mega:restic-backup";
        passwordFile = "/var/lib/secrets/restic_password";
        environmentFile = "/var/lib/secrets/restic_mega_creds";

        paths = [
          "${cfgImp.persistMountPoint}/var/lib/secrets"
          "${cfgImp.persistMountPoint}/var/lib/vaultwarden"
          "${cfgImp.persistMountPoint}/var/lib/pocket-id"
        ];

        exclude = [
          "**/cache/**"
          "**/*.log"
        ];

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
        ];

        timerConfig = {
          OnCalendar = "Sun *-*-* 04:00:00";
          Persistent = true;
        };

        backupPrepareCommand = ''
          systemctl stop vaultwarden pocket-id || true
        '';

        backupCleanupCommand = ''
          systemctl start vaultwarden pocket-id || true
        '';
      };

      # rclone muss im PATH des restic-Services liegen (MEGA-Backend)
      systemd.services."restic-backups-tier-a-mega".path = [ pkgs.rclone ];
    })
  ];
}

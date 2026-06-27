# ---
# meta:
#   layer: 3
#   role: module
#   purpose: AMP Game-Server-Manager in FHS-Sandbox
#   services:
#     - amp
#   tags:
#     - gaming
#     - amp
# ---
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.services.amp;

  ampBin = "${cfg.dataDir}/opt/cubecoders/amp/ampinstmgr";

  # FHS Sandbox Environment for running unpatched game servers inside AMP
  amp-fhs = pkgs.buildFHSEnv {
    name = "amp-fhs";
    targetPkgs = pkgs:
      with pkgs; [
        dotnet-sdk_8
        glibc
        glibc.dev
        stdenv.cc.cc.lib # libstdc++
        openssl
        curl
        sqlite
        screen
        tmux
        socat
        git
        jq
        qrencode
        wget
        bind
        bash
        coreutils
        procps
        findutils
        gnutar
        gzip
        unzip
        xz
        steamcmd
        icu
        zlib
        krb5
      ];
    multiPkgs = pkgs:
      with pkgs; [
        pkgsi686Linux.glibc
      ];
    runScript = "bash";
  };

  ampBootstrap = pkgs.writeShellScript "amp-bootstrap" ''
        set -euo pipefail
        DATA_DIR="${cfg.dataDir}"
        AMP_BIN="${ampBin}"
        TARBALL_URL="https://repo.cubecoders.com/ampinstmgr-latest.tgz"
        PORT="${toString cfg.port}"
        FHS="${amp-fhs}/bin/amp-fhs"
        SECRETS="/var/lib/secrets/amp.env"

        if [ ! -f "$SECRETS" ]; then
          echo "amp.env fehlt — secrets.devKeys.amp in profile.local.nix setzen" >&2
          exit 1
        fi
        # shellcheck source=/dev/null
        source "$SECRETS"
        : "''${AMP_ADMIN_USER:?AMP_ADMIN_USER fehlt in amp.env}"
        : "''${AMP_ADMIN_PASSWORD:?AMP_ADMIN_PASSWORD fehlt in amp.env}"

        if [ ! -x "$AMP_BIN" ]; then
          echo "Lade AMP Instance Manager von $TARBALL_URL ..."
          tmp=$(mktemp -d)
          trap 'rm -rf "$tmp"' EXIT
          ${pkgs.curl}/bin/curl -fsSL "$TARBALL_URL" -o "$tmp/ampinstmgr.tgz"
          ${pkgs.gnutar}/bin/tar -xzf "$tmp/ampinstmgr.tgz" -C "$DATA_DIR"
          chown -R amp:amp "$DATA_DIR/opt" "$DATA_DIR/etc" 2>/dev/null || true
        fi

        install -d -m 755 -o amp -g amp "$DATA_DIR/etc"
        cat > "$DATA_DIR/etc/ampinstmgr.conf" <<'EOF'
    ampinstmgr.startonboot=amp
    ampinstmgr.updatefirewall=
    ampinstmgr.upnpsyncenabled=false
    EOF
        chown amp:amp "$DATA_DIR/etc/ampinstmgr.conf"

        ${pkgs.systemd}/bin/loginctl enable-linger amp 2>/dev/null || true

        run_amp() {
          ${pkgs.util-linux}/bin/runuser -u amp -- env HOME="$DATA_DIR" "$FHS" -c "cd \"$DATA_DIR\" && $*"
        }

        instances_root="$DATA_DIR/.ampdata/instances"

        valid_instance() {
          local name="$1"
          [ -n "$name" ] || return 1
          [ "$name" != "No" ] || return 1
          [ -d "$instances_root/$name" ] && \
            [ -n "$(find "$instances_root/$name" -maxdepth 1 -name 'AMP_*' -print -quit 2>/dev/null)" ]
        }

        list_instances() {
          [ -d "$instances_root" ] || return 0
          find "$instances_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
        }

        # Kaputte Reste von fehlgeschlagenen Creates entfernen
        while IFS= read -r stale; do
          [ -n "$stale" ] || continue
          if ! valid_instance "$stale"; then
            echo "Entferne ungültige AMP-Instanz: $stale"
            run_amp "\"$AMP_BIN\" -d \"$stale\" true" 2>/dev/null || \
              rm -rf "$instances_root/$stale"
          fi
        done < <(list_instances)

        instance=""
        while IFS= read -r candidate; do
          if valid_instance "$candidate"; then
            instance="$candidate"
            break
          fi
        done < <(list_instances)

        if [ -z "$instance" ]; then
          echo "Erstelle ADS-Instanz (CubeCoders -quick) ..."
          # -quick blockiert bis Browser-Setup fertig — wir warten nur auf laufende Instanz
          run_amp "\"$AMP_BIN\" -quick \"$AMP_ADMIN_USER\" \"$AMP_ADMIN_PASSWORD\" 127.0.0.1 $PORT +Core.Webserver.UsingReverseProxy True +Core.Webserver.Port $PORT" &
          quick_pid=$!
          for _ in $(seq 1 120); do
            while IFS= read -r candidate; do
              if valid_instance "$candidate"; then
                instance="$candidate"
                break 2
              fi
            done < <(list_instances)
            sleep 2
          done
          kill -INT "$quick_pid" 2>/dev/null || true
          wait "$quick_pid" 2>/dev/null || true
        else
          echo "AMP-Instanz vorhanden: $instance"
        fi

        if [ -n "$instance" ]; then
          run_amp "\"$AMP_BIN\" -q \"$instance\"" 2>/dev/null || true
          # ADS-Rebind fragt interaktiv nach Bestätigung — für Headless mit "Y" beantworten
          run_amp "printf 'Y\\n' | \"$AMP_BIN\" --RebindInstance \"$instance\" 127.0.0.1 $PORT" || true
          run_amp "\"$AMP_BIN\" --ReconfigureInstance \"$instance\" +Core.Webserver.UsingReverseProxy True +Core.Webserver.Port $PORT" || true
          run_amp "\"$AMP_BIN\" -x \"$instance\" true" || true
          run_amp "\"$AMP_BIN\" -s \"$instance\"" || true
        else
          echo "Keine gültige AMP-Instanz — QuickStart fehlgeschlagen?" >&2
          exit 1
        fi
  '';
in {
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.amp = {
    enable = lib.mkEnableOption "AMP Game Server Manager";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.amp;
      description = "AMP Web UI port.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/amp";
      description = "AMP data directory.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # ── 1. SYSTEM PACKAGES ───────────────────────────────────────────────────
    environment.systemPackages = [amp-fhs];

    # ── 2. BOOTSTRAP + SYSTEMD ───────────────────────────────────────────────
    systemd.services.amp-bootstrap = {
      description = "Install CubeCoders AMP (ampinstmgr + ADS instance)";
      after = [
        "network-online.target"
        "q958-secrets-provision.service"
      ];
      wants = [
        "network-online.target"
        "q958-secrets-provision.service"
      ];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ampBootstrap;
      };
    };

    systemd.services.amp = {
      description = "AMP Game Server Manager (Native FHS)";
      after = [
        "amp-bootstrap.service"
        "network-online.target"
      ];
      wants = ["network-online.target"];
      requires = ["amp-bootstrap.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${amp-fhs}/bin/amp-fhs -c '${ampBin} startboot true'";
        ExecStop = "${amp-fhs}/bin/amp-fhs -c '${ampBin} stopall'";
        User = "amp";
        Group = "amp";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = "30s";
        TimeoutStartSec = "300s";
        TimeoutStopSec = "180s";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        ReadWritePaths = [cfg.dataDir];
        PrivateNetwork = false;
        PrivateUsers = false;
        PrivateDevices = false;
      };
    };

    # ── 3. SYSTEM USER ────────────────────────────────────────────────────────
    users.users.amp = {
      isSystemUser = true;
      group = "amp";
      home = cfg.dataDir;
      createHome = true;
      shell = "${amp-fhs}/bin/amp-fhs";
    };
    users.groups.amp = {};

    # ── 4. DIRECTORY CREATION ─────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 amp amp -"
    ];

    my.impermanence.extraPaths = [cfg.dataDir];
  };
}

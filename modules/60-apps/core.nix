{ config, lib, pkgs, ... }:

let
  cfgVaultwarden = config.my.services.vaultwarden;
  cfgHomepage = config.my.services.homepage;
  cfgFilebrowser = config.my.services.filebrowser;
  cfgLinkwarden = config.my.services.linkwarden;
  cfgOpenWebui = config.my.services.open-webui;

  domain = config.my.configs.identity.domain;
  portVaultwarden = config.my.ports.vaultwarden;
  portHomepage = config.my.ports.homepage;

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgVaultwarden.enable {


      services.vaultwarden = {
        enable = true;
        dbBackend = "sqlite"; # Lokale SQLite DB für minimale externe Latenz
        environmentFile = "/home/moritz/secrets/vaultwarden.env";

        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = portVaultwarden;
          DOMAIN = "https://vault.${domain}";

          # Security defaults
          SIGNUPS_ALLOWED = false;
          INVITATIONS_ALLOWED = true;
          SHOW_PASSWORD_HINT = false;
          DISABLE_ADMIN_TOKEN = false; # Ermöglicht administrative Zugriffe

          # Concurrency
          DATABASE_MAX_CONNS = 10; # WAL mode Concurrency

          # Brute-Force Rate Limiting
          LOGIN_RATELIMIT_MAX_BURST = 10;
          LOGIN_RATELIMIT_SECONDS = 60;

          REQUIRE_DEVICE_EMAIL = false;

          ICON_DOWNLOAD_TIMEOUT = 0; # IP-Leakage Schutz

          LOG_LEVEL = "info"; # Für Fail2Ban parsing
          EXTENDED_LOGGING = true;
          LOG_FILE = "/var/log/vaultwarden/vaultwarden.log";
          DATA_FOLDER = "/data/state/vaultwarden";
        };
      };

      # Log-Ordner Bereitstellung
      systemd.tmpfiles.rules = [
        "d /var/log/vaultwarden 0750 vaultwarden vaultwarden -"
      ];

      # Caddy Reverse Proxy (Websockets laufen nativ auf Hauptport)
      services.caddy.virtualHosts."vault.${domain}" = {
        extraConfig = ''
          import security_headers
          reverse_proxy 127.0.0.1:${toString portVaultwarden}
        '';
      };

      # Systemd Security Hardening
      systemd.services.vaultwarden.serviceConfig = {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        ProtectKernelTunables = lib.mkForce true;
        ProtectKernelModules = lib.mkForce true;
        ProtectControlGroups = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        MemoryDenyWriteExecute = lib.mkForce true;
        LockPersonality = lib.mkForce true;
        RestrictRealtime = lib.mkForce true;
        RestrictSUIDSGID = lib.mkForce true;
        CapabilityBoundingSet = lib.mkForce "";
        DevicePolicy = lib.mkForce "closed";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        ReadWritePaths = [
          "/data/state/vaultwarden"
          "/var/log/vaultwarden"
        ];
        EnvironmentFile = lib.mkForce "/home/moritz/secrets/vaultwarden.env";
      };
    })

    (lib.mkIf cfgHomepage.enable {
      services.homepage-dashboard = {
        enable = true;
        listenPort = portHomepage;

        settings = {
          title = "Mäusekino";
          background = {
            image = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
            blur = "xl";
            saturate = 50;
            brightness = 25;
            opacity = 40;
          };
          headerStyle = "clean";
          cardBlur = "sm";
          iconStyle = "theme";
          layout = [
            {
              "Medien & Player" = {
                style = "row";
                columns = 4;
              };
            }
            {
              "Downloads & Arrs" = {
                style = "row";
                columns = 5;
              };
            }
            {
              "Tools" = {
                style = "row";
                columns = 6;
              };
            }
            {
              "System" = {
                style = "row";
                columns = 5;
              };
            }
            {
              "KI & Agenten" = {
                style = "row";
                columns = 2;
              };
            }
          ];
        };

        bookmarks = [
          {
            Developer = [
              {
                Github = [
                  {
                    abbr = "GH";
                    href = "https://github.com/";
                  }
                ];
              }
            ];
          }
          {
            Social = [
              {
                Reddit = [
                  {
                    abbr = "RE";
                    href = "https://reddit.com/";
                  }
                ];
              }
            ];
          }
          {
            Entertainment = [
              {
                YouTube = [
                  {
                    abbr = "YT";
                    href = "https://youtube.com/";
                  }
                ];
              }
            ];
          }
        ];

        services = [
          {
            "Medien & Player" = [
              {
                Jellyfin = {
                  href = "https://jellyfin.${domain}";
                  description = "Filme & Serien";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg";
                };
              }
              {
                Seerr = {
                  href = "https://seerr.${domain}";
                  description = "Medienanfragen";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyseerr.svg";
                };
              }
              {
                Audiobookshelf = {
                  href = "https://audiobookshelf.${domain}";
                  description = "Hörbücher & Podcasts";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/audiobookshelf.svg";
                };
              }
              {
                ReadMeABook = {
                  href = "https://audiobooks.${domain}";
                  description = "Hörbuch-Wünsche";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/read-me-a-book.png";
                };
              }
            ];
          }
          {
            "Downloads & Arrs" = [
              {
                Sonarr = {
                  href = "https://sonarr.${domain}";
                  description = "Serien";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/sonarr.svg";
                };
              }
              {
                Radarr = {
                  href = "https://radarr.${domain}";
                  description = "Filme";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/radarr.svg";
                };
              }
              {
                Readarr = {
                  href = "https://readarr.${domain}";
                  description = "Bücher";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/readarr.svg";
                };
              }
              {
                Prowlarr = {
                  href = "https://prowlarr.${domain}";
                  description = "Indexer";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prowlarr.svg";
                };
              }
              {
                SABnzbd = {
                  href = "https://sabnzbd.${domain}";
                  description = "Usenet-Downloader";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/sabnzbd.svg";
                };
              }
            ];
          }
          {
            "Tools" = [
              {
                Vaultwarden = {
                  href = "https://vaultwarden.${domain}";
                  description = "Passwörter";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/vaultwarden.svg";
                };
              }
              {
                Linkding = {
                  href = "https://linkding.${domain}";
                  description = "Lesezeichen";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/linkding.svg";
                };
              }
              {
                Readeck = {
                  href = "https://readeck.${domain}";
                  description = "Read Later";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/readeck.svg";
                };
              }
              {
                BentoPDF = {
                  href = "https://bentopdf.${domain}";
                  description = "PDF Tools";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/stirling-pdf.svg";
                };
              }
              {
                "Open WebUI" = {
                  href = "https://ai.${domain}";
                  description = "KI-Interface";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/open-webui.svg";
                };
              }
              {
                "Pocket ID" = {
                  href = "https://auth.${domain}";
                  description = "Authentifizierung";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/pocket-id.svg";
                };
              }
            ];
          }
          {
            "System" = [
              {
                Unraid = {
                  href = "https://unraid.${domain}";
                  description = "Server-Verwaltung";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/unraid.svg";
                };
              }
              {
                Traefik = {
                  href = "https://traefik.${domain}";
                  description = "Reverse Proxy";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/traefik.svg";
                };
              }
              {
                Semaphore = {
                  href = "https://semaphore.${domain}";
                  description = "Ansible UI";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/semaphore.svg";
                };
              }
              {
                Speedtest = {
                  href = "https://speedtest.${domain}";
                  description = "Netzwerk-Test";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/speedtest-tracker.svg";
                };
              }
              {
                "DDNS Updater" = {
                  href = "https://ddns.${domain}";
                  description = "Dynamisches DNS";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cloudflare.svg";
                };
              }
            ];
          }
          {
            "KI & Agenten" =
              (lib.optional (cfgHomepage.agentZeroUrl != "") {
                "Agent Zero" = {
                  href = cfgHomepage.agentZeroUrl;
                  description = "KI-Agent";
                  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/agent-zero.svg";
                };
              })
              ++ [
                {
                  OpenClaw = {
                    href = "https://openclaw.${domain}";
                    description = "Research Tool";
                    icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/openai.svg";
                  };
                }
              ];
          }
        ];

        customCSS = ''
          /* 🛠️ Mäusekino - Tieferlegung und radikale Bereinigung */

          /* 1. Alles, was nicht 'Sehen' oder 'Hören' ist, wird gnadenlos ausgeblendet */
          #search, .search-container, #widgets, .widgets-container, .footer, .stats-container {
              display: none !important;
              visibility: hidden !important;
              height: 0 !important;
              margin: 0 !important;
              padding: 0 !important;
          }

          /* 2. Den gesamten App-Inhalt massiv nach unten schieben */
          #app, .layout-wrapper {
              padding-top: 30vh !important; /* 30% des Bildschirms von oben Platz lassen */
              display: flex !important;
              flex-direction: column !important;
              align-items: center !important;
          }

          /* 3. Den Titel 'Mäusekino' sauber über den Gruppen positionieren */
          header, .header {
              text-align: center !important;
              margin-bottom: 40px !important;
              font-size: 2.5rem !important;
          }

          /* 4. Die Gruppen-Container mittig ausrichten */
          .group-wrapper, .groups-container {
              display: flex !important;
              justify-content: center !important;
              gap: 50px !important; /* Abstand zwischen Sehen und Hören */
              width: 100% !important;
          }
        '';

        customJS = ''
          (function() {
              const applyTheme = () => {
                  const theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
                  document.documentElement.classList.remove('dark', 'light');
                  document.documentElement.classList.add(theme);
                  localStorage.setItem('theme-mode', theme);
              };

              // Apply on load
              applyTheme();

              // Watch for changes
              window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyTheme);
          })();
        '';
      };

      services.caddy.virtualHosts."dashboard.${domain}" = {
        extraConfig = ''
          import security_headers
          reverse_proxy 127.0.0.1:${toString portHomepage}
        '';
      };
    })

    (lib.mkIf cfgFilebrowser.enable {
      services.filebrowser = {
        enable = true;
        settings = {
          inherit (cfgFilebrowser) port;
          address = "127.0.0.1";
          root = cfgFilebrowser.rootPath;
          database = cfgFilebrowser.databasePath;
        };
      };

      services.caddy.virtualHosts."files.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgFilebrowser.port}
        '';
      };

      systemd.services.filebrowser.serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        OOMScoreAdjust = 300;
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        ProtectClock = true;
        ProtectHostname = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };
    })

    (lib.mkIf cfgLinkwarden.enable {


      services.linkwarden = {
        enable = true;
        inherit (cfgLinkwarden) port;
        environmentFile = "/home/moritz/secrets/linkwarden.env";
        environment = {
          NEXTAUTH_URL = "https://links.${domain}/api/v1/auth";
        };
      };

      services.caddy.virtualHosts."links.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgLinkwarden.port}
        '';
      };

      systemd.services.linkwarden = {
        serviceConfig = {
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          SystemCallFilter = [ "@system-service" "~@privileged" ];
          OOMScoreAdjust = 300;
          StateDirectory = "linkwarden";
          CapabilityBoundingSet = "";
          RestrictNamespaces = true;
          ProtectClock = true;
          ProtectHostname = true;
          LockPersonality = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        };
      };
    })

    (lib.mkIf cfgOpenWebui.enable {
      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        inherit (cfgOpenWebui) port;
        environment = {
          OLLAMA_API_BASE_URL = cfgOpenWebui.ollamaUrl;
          SCARF_NO_ANALYTICS = "True";
          DO_NOT_TRACK = "True";
          ANONYMIZED_TELEMETRY = "False";
        };
      };

      services.caddy.virtualHosts."ai.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgOpenWebui.port}
        '';
      };

      systemd.services.open-webui.serviceConfig = {
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        SupplementaryGroups = [ "render" "video" ];
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        OOMScoreAdjust = 200;
      };
    })
  ];
}


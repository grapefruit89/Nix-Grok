{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgHomepage = config.my.services.homepage;
  domain = config.my.configs.identity.domain;
  portHomepage = config.my.ports.homepage;

in
{
  config = lib.mkIf cfgHomepage.enable {
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

    services.caddy.virtualHosts."homepage.${domain}" = {
      extraConfig = caddy.proxyTailscaleSso portHomepage;
    };

    systemd.services.homepage-dashboard.serviceConfig.OOMScoreAdjust = 500;
  };
}


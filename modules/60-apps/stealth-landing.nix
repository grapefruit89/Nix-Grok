{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.stealth-landing;
  domain = config.my.configs.identity.domain;

  indexHtml = pkgs.writeText "index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>System</title>
      <style>
        :root {
          /* Modern oklch deep marine blue */
          --bg-color: oklch(18% 0.03 260);
          --icon-fill: oklch(40% 0.02 260);
          --icon-hover: oklch(70% 0.05 260);
        }

        body {
          background-color: var(--bg-color);
          margin: 0;
          min-height: 100dvh;
          display: grid;
          place-items: center;
          align-content: center;
          gap: 3rem;
          grid-auto-flow: column;
        }

        svg {
          width: clamp(40px, 5vw, 60px);
          height: clamp(40px, 5vw, 60px);
          fill: var(--icon-fill);
          cursor: pointer;
          transition: fill 0.4s cubic-bezier(0.4, 0, 0.2, 1), transform 0.4s cubic-bezier(0.4, 0, 0.2, 1);
        }

        svg:hover {
          fill: var(--icon-hover);
          transform: scale(1.1);
        }

        /* 
         * The "Reklametafel" Honeypot:
         * Completely visible to the DOM and CSSOM layout engine of a bot.
         * Same color as the background, unclickable by humans (pointer-events: none),
         * and layered behind everything (z-index: -1).
         */
        .trap-container {
          position: fixed;
          inset: 0;
          z-index: -1;
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: center;
          gap: 2rem;
          pointer-events: none;
          user-select: none;
        }

        .trap-container a {
          color: var(--bg-color);
          text-decoration: none;
          font-size: 2rem;
        }
      </style>
    </head>
    <body>

      <div class="trap-container" aria-hidden="true">
        <a href="/.env">System Environment Variables</a>
        <a href="/wp-admin">Wordpress Administration Panel</a>
        <a href="/config.json">Global Application Configuration</a>
        <a href="/db.sql">Database Dump Backup</a>
        <a href="/phpinfo.php">PHP Server Information</a>
      </div>

      <!-- Jellyfin SVG -->
      <svg data-route="aHR0cHM6Ly9qZWxseWZpbi5tN2M1LmRl" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>
      
      <!-- Jellyseerr SVG -->
      <svg data-route="aHR0cHM6Ly9zZWVyci5tN2M1LmRl" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>

      <!-- Audiobookshelf SVG -->
      <svg data-route="aHR0cHM6Ly9hdWRpb2Jvb2tzaGVsZi5tN2M1LmRl" viewBox="0 0 24 24"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>

      <!-- Navidrome SVG -->
      <svg data-route="aHR0cHM6Ly9uYXZpZHJvbWUubTdjNS5kZQ==" viewBox="0 0 24 24"><path d="M12 3c-4.97 0-9 4.03-9 9v7c0 1.1.9 2 2 2h4v-8H5v-1c0-3.87 3.13-7 7-7s7 3.13 7 7v1h-4v8h4c1.1 0 2-.9 2-2v-7c0-4.97-4.03-9-9-9z"/></svg>

      <script type="module">
        // Modern event delegation for routing
        document.body.addEventListener('click', (e) => {
          const target = e.target.closest('svg[data-route]');
          if (target) {
            window.location.assign(atob(target.dataset.route));
          }
        });
      </script>
    </body>
    </html>
  '';

in
{
  options.my.services.stealth-landing = {
    enable = lib.mkEnableOption "Stealth Landingpage on Root Domain";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/www/stealth 0755 caddy caddy"
      "L+ /var/www/stealth/index.html - - - - ${indexHtml}"
    ];

    services.caddy.virtualHosts."${domain}" = {
      extraConfig = ''
        root * /var/www/stealth
        file_server

        # Honeypot: Instant 403 triggers fail2ban
        @honeypot {
          path /.env /wp-admin /wp-login.php /config.json /db.sql /phpinfo.php /admin /.git
        }
        handle @honeypot {
          respond 403 { close }
        }

        # Catch-All Drop: Only allow root path
        @notroot {
          not path /
        }
        handle @notroot {
          respond 403 { close }
        }
      '';
    };
  };
}

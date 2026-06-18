{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.stealth-landing;
  domain = config.my.configs.identity.domain;

  indexHtml = pkgs.writeText "index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>Stealth</title>
      <style>
        body {
          background-color: #0b1121;
          color: #000;
          display: flex;
          justify-content: center;
          align-items: center;
          height: 100vh;
          margin: 0;
          gap: 40px;
        }
        svg {
          width: 50px;
          height: 50px;
          fill: #333;
          cursor: pointer;
          transition: fill 0.3s;
        }
        svg:hover {
          fill: #555;
        }
        /* Honeypot Links (Invisible to Humans, Visible to DOM Scrapers) */
        a.trap {
          position: absolute;
          left: -9999px;
          opacity: 0.01;
        }
      </style>
    </head>
    <body>

      <!-- Invisible Honeypots for Bots -->
      <a class="trap" href="/.env">ENV</a>
      <a class="trap" href="/wp-admin">Admin</a>
      <a class="trap" href="/config.json">Config</a>
      <a class="trap" href="/db.sql">DB</a>
      <a class="trap" href="/phpinfo.php">Info</a>

      <!-- Jellyfin SVG -->
      <svg id="jf" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>
      
      <!-- Jellyseerr SVG -->
      <svg id="js" viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>

      <!-- Audiobookshelf SVG -->
      <svg id="ab" viewBox="0 0 24 24"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>

      <!-- Navidrome SVG -->
      <svg id="nd" viewBox="0 0 24 24"><path d="M12 3c-4.97 0-9 4.03-9 9v7c0 1.1.9 2 2 2h4v-8H5v-1c0-3.87 3.13-7 7-7s7 3.13 7 7v1h-4v8h4c1.1 0 2-.9 2-2v-7c0-4.97-4.03-9-9-9z"/></svg>

      <script>
        // aHR0cHM6Ly9qZWxseWZpbi5tN2M1LmRl = https://jellyfin.m7c5.de
        // aHR0cHM6Ly9zZWVyci5tN2M1LmRl = https://seerr.m7c5.de
        // aHR0cHM6Ly9hdWRpb2Jvb2tzaGVsZi5tN2M1LmRl = https://audiobookshelf.m7c5.de
        // aHR0cHM6Ly9uYXZpZHJvbWUubTdjNS5kZQ== = https://navidrome.m7c5.de

        document.getElementById('jf').onclick = function() { window.location.href = atob('aHR0cHM6Ly9qZWxseWZpbi5tN2M1LmRl'); };
        document.getElementById('js').onclick = function() { window.location.href = atob('aHR0cHM6Ly9zZWVyci5tN2M1LmRl'); };
        document.getElementById('ab').onclick = function() { window.location.href = atob('aHR0cHM6Ly9hdWRpb2Jvb2tzaGVsZi5tN2M1LmRl'); };
        document.getElementById('nd').onclick = function() { window.location.href = atob('aHR0cHM6Ly9uYXZpZHJvbWUubTdjNS5kZQ=='); };
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

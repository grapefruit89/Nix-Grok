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
          --bg-dark: oklch(14% 0.01 260);
          --card-bg: oklch(100% 0 0 / 0.02);
          --card-bg-hover: oklch(100% 0 0 / 0.06);
          --card-border: oklch(100% 0 0 / 0.05);
          --card-border-hover: oklch(100% 0 0 / 0.15);
          --icon-color: oklch(65% 0.05 260);
          --icon-hover: oklch(95% 0.1 260);
          --shadow-color: oklch(0% 0 0 / 0.5);
          --glow-color: oklch(70% 0.15 260 / 0.4);
        }

        body {
          margin: 0;
          min-height: 100dvh;
          background-color: var(--bg-dark);
          overflow: hidden;
          display: grid;
          place-items: center;
          font-family: system-ui, -apple-system, sans-serif;
        }

        .bg-orb {
          position: absolute;
          border-radius: 50%;
          filter: blur(100px);
          z-index: -2;
          animation: orb-move 25s infinite alternate ease-in-out;
          pointer-events: none;
        }

        .orb-1 {
          width: 50vw;
          height: 50vw;
          max-width: 600px;
          max-height: 600px;
          background: oklch(40% 0.12 260 / 0.3);
          top: -10%;
          left: -10%;
        }

        .orb-2 {
          width: 60vw;
          height: 60vw;
          max-width: 700px;
          max-height: 700px;
          background: oklch(30% 0.15 280 / 0.25);
          bottom: -20%;
          right: -10%;
          animation-delay: -10s;
        }

        @keyframes orb-move {
          0% { transform: translate(0, 0) scale(1); }
          100% { transform: translate(5vw, 5vh) scale(1.1); }
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
          color: var(--bg-dark);
          text-decoration: none;
          font-size: 2rem;
        }

        .dashboard {
          display: flex;
          flex-wrap: wrap;
          justify-content: center;
          gap: 2rem;
          padding: 2rem;
          z-index: 1;
        }

        @keyframes float {
          0%, 100% { transform: translateY(0px); }
          50% { transform: translateY(-10px); }
        }

        .card-wrapper {
          animation: float 7s ease-in-out infinite;
        }
        
        .card-wrapper:nth-child(2) { animation-delay: -1.5s; }
        .card-wrapper:nth-child(3) { animation-delay: -3.0s; }
        .card-wrapper:nth-child(4) { animation-delay: -4.5s; }

        .card {
          background: var(--card-bg);
          border: 1px solid var(--card-border);
          border-radius: 28px;
          padding: 2.5rem;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          backdrop-filter: blur(24px);
          -webkit-backdrop-filter: blur(24px);
          box-shadow: 0 8px 32px var(--shadow-color), inset 0 1px 0 oklch(100% 0 0 / 0.1);
          transition: all 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275);
          text-decoration: none;
          color: inherit;
          
          &:hover {
            background: var(--card-bg-hover);
            border-color: var(--card-border-hover);
            transform: translateY(-8px) scale(1.08);
            box-shadow: 0 24px 48px var(--shadow-color), 0 0 40px var(--glow-color), inset 0 1px 0 oklch(100% 0 0 / 0.2);
          }

          & svg {
            width: clamp(48px, 6vw, 72px);
            height: clamp(48px, 6vw, 72px);
            fill: var(--icon-color);
            transition: all 0.5s ease;
            filter: drop-shadow(0 4px 6px var(--shadow-color));
          }

          &:hover svg {
            fill: var(--icon-hover);
            transform: scale(1.1);
            filter: drop-shadow(0 0 15px var(--glow-color));
          }
        }
      </style>
    </head>
    <body>
      <div class="bg-orb orb-1"></div>
      <div class="bg-orb orb-2"></div>

      <div class="trap-container" aria-hidden="true">
        <a href="/.env">System Environment Variables</a>
        <a href="/wp-admin">Wordpress Administration Panel</a>
        <a href="/config.json">Global Application Configuration</a>
        <a href="/db.sql">Database Dump Backup</a>
        <a href="/phpinfo.php">PHP Server Information</a>
      </div>

      <div class="dashboard">
        <!-- App 1 -->
        <div class="card-wrapper">
          <div class="card" data-id="1">
            <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>
          </div>
        </div>
        
        <!-- App 2 -->
        <div class="card-wrapper">
          <div class="card" data-id="2">
            <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>
          </div>
        </div>

        <!-- App 3 -->
        <div class="card-wrapper">
          <div class="card" data-id="3">
            <svg viewBox="0 0 24 24"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>
          </div>
        </div>

        <!-- App 4 -->
        <div class="card-wrapper">
          <div class="card" data-id="4">
            <svg viewBox="0 0 24 24"><path d="M12 3c-4.97 0-9 4.03-9 9v7c0 1.1.9 2 2 2h4v-8H5v-1c0-3.87 3.13-7 7-7s7 3.13 7 7v1h-4v8h4c1.1 0 2-.9 2-2v-7c0-4.97-4.03-9-9-9z"/></svg>
          </div>
        </div>
      </div>

      <script type="module">
        document.body.addEventListener('click', (e) => {
          if (!e.isTrusted) return;
          const card = e.target.closest('.card[data-id]');
          if (card) {
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = '/go/' + card.dataset.id;
            document.body.appendChild(form);
            form.submit();
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

        # Stealth POST Routing
        @go_post {
          method POST
          path /go/*
        }
        handle @go_post {
          @app1 path /go/1
          redir @app1 https://jellyfin.''${domain} 303
          
          @app2 path /go/2
          redir @app2 https://seer.''${domain} 303
          
          @app3 path /go/3
          redir @app3 https://audiobookshelf.''${domain} 303
          
          @app4 path /go/4
          redir @app4 https://navidrome.''${domain} 303
        }

        # Catch-All Drop: Only allow root path and /go/*
        @notroot {
          not path / /go/*
        }
        handle @notroot {
          respond 403 { close }
        }
      '';
    };
  };
}

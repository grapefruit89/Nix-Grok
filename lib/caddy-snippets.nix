# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Gemeinsame Caddyfile-Snippets — SSO, Security-Header, Private-Admin
#   tags:
#     - caddy
#     - snippets
#   docs:
#     - docs/adr/014-caddy-security-headers-trusted-proxies.md
#     - docs/adr/016-caddy-security-headers-coop-scanners.md
#     - docs/adr/017-caddy-health-checks-error-fallback.md
# ---
{
  lib,
  pocketIdPort,
  lanCidr ? "192.168.0.0/16",
}:
let
  privateCidr = "100.64.0.0/10";
in
{
  extraConfig = ''
    (security_headers) {
      header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-XSS-Protection "0"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "upgrade-insecure-requests"
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
        Cross-Origin-Opener-Policy "same-origin"
        -Server
      }
    }

    (private_admin) {
      @external not remote_ip ${privateCidr} 127.0.0.0/8 ::1/128 ${lanCidr}
      respond @external "Forbidden" 403
    }

    (streamer_headers) {
      header Cache-Control "no-store, no-cache, must-revalidate, private"
      header -ETag
    }

    (block_scanners) {
      @scanners header User-Agent *shodan* *masscan* *zgrab* *nmap* *python-requests* *censys* *nuclei*
      @no_ua {
        not header User-Agent *
        not remote_ip private_ranges ${privateCidr} ${lanCidr}
      }
      abort @scanners
      abort @no_ua
    }

    (block_attack_paths) {
      @vuln_paths path /.env* /.git/* /wp-admin/* /wp-login.php /xmlrpc.php /.aws/* /.ssh/* /.htaccess /.htpasswd /server-status /server-info /phpinfo.php /actuator/* /.DS_Store
      abort @vuln_paths
    }

    (block_bad_methods) {
      @bad_methods not method GET POST PUT PATCH DELETE HEAD OPTIONS
      abort @bad_methods
    }

    # Wenn ein Upstream nicht erreichbar ist (502/503), sauber mit 503 antworten
    # statt roher "Bad Gateway"-Seite. Wird in jeden vHost importiert.
    (upstream_errors) {
      handle_errors 502 503 {
        respond "Service momentan nicht verfügbar" 503
      }
    }
  ''
  + lib.optionalString (pocketIdPort != null) ''
    (sso_auth) {
      forward_auth 127.0.0.1:${toString pocketIdPort} {
        uri /api/auth/verify
        copy_headers X-Forwarded-User X-Forwarded-Method X-Forwarded-Uri
        transport http {
          keepalive 30s
          keepalive_idle_conns 10
        }
      }
    }
  '';
}

# Shared Caddyfile snippets — homelab_server Kirschen (kein Geo in Caddy, nie)
#
# sso_auth     → Browser-Dienste (*arr, Paperless, Jellyfin-Browser, …)
# NICHT für    → Jellyfin-Apps (X-Emby-Authorization), auth.* (Deadlock)
{ lib, pocketIdPort, lanCidr ? "192.168.0.0/16" }:

let
  tailscaleCidr = "100.64.0.0/10";
in
{
  extraConfig =
    ''
      (security_headers) {
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-XSS-Protection "1; mode=block"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Content-Security-Policy "upgrade-insecure-requests"
        }
      }

      (tailscale_admin) {
        @external not remote_ip ${tailscaleCidr} 127.0.0.0/8 ::1/128 ${lanCidr}
        respond @external "Forbidden" 403
      }

      (streamer_headers) {
        header Cache-Control "no-store, no-cache, must-revalidate, private"
        header -ETag
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

      (sso_auth_bypass) {
        @nativeApp {
          header_regexp User-Agent (?i)(jellyfin|emby|kodi|roku|firetv|appletv|swiftfin|findroid)
        }
        @requireSso {
          not matcher @nativeApp
        }
        forward_auth @requireSso 127.0.0.1:${toString pocketIdPort} {
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
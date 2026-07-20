# ---
# meta:
#   id: NIXH-10-ING-001
#   layer: 3
#   role: module
#   purpose: Spez-basierter Caddy-Ingress — einzige Quelle für vHosts
#   lib:
#     - lib/caddy-ingress.nix
#     - lib/service-enable.nix
#   docs:
#     - docs/adr/1017-caddy-health-checks-error-fallback.md
#   tags:
#     - caddy
#     - ingress
# ---
{
  lib,
  caddy,
}:
let
  inherit (caddy) streamingBackend;

  vpnUpstream = _name: mkUpstream;

  mkUpstream =
    entry:
    if entry.socket or null != null then "unix/${entry.socket}" else "127.0.0.1:${toString entry.port}";

  mkFqdn = domain: entry: "${entry.subdomain}.${domain}";

  l7GuardImports = ''
    import block_scanners
    import block_attack_paths
    import block_bad_methods
  '';

  genAuthVhost = upstream: ''
    import security_headers
    import upstream_errors
    import sso_redirect
    handle /api/auth/* {
      reverse_proxy ${upstream}
    }
    handle /.well-known/* {
      reverse_proxy ${upstream}
    }
    handle /admin/* {
      import private_admin
      reverse_proxy ${upstream}
    }
    handle {
      import sso_auth
      reverse_proxy ${upstream}
    }
  '';

  genJellyfinVhost = port: ''
    import streamer_headers
    import security_headers
    import upstream_errors
    import sso_redirect

    @jellyfin_auth_header header_regexp X-Emby-Authorization (?i)MediaBrowser
    @jellyfin_api_paths path /system/info/public /emby/system/info/public /Users/AuthenticateByName /emby/Users/AuthenticateByName /dlna/* /socket/*
    @jellyfin_ua header User-Agent *Jellyfin* *Kodi* *Roku* *Infuse* *AppleTV* *FindMySync* *NativeHost*

    handle @jellyfin_auth_header {
      ${streamingBackend port}
    }
    handle @jellyfin_api_paths {
      ${streamingBackend port}
    }
    handle @jellyfin_ua {
      ${streamingBackend port}
    }

    handle {
      import sso_auth
      ${streamingBackend port}
    }
  '';

  # Navidrome: SSO für Web-UI; SubSonic/OpenSubsonic-Clients (/rest/*) und Share-Links (/share/*)
  # dürfen nicht durch SSO — sie nutzen Token-Auth in der URL/Header.
  genNavidromeVhost = port: ''
    import streamer_headers
    import security_headers
    import upstream_errors
    import sso_redirect

    @navidrome_api {
      path /rest/*
      path /share/*
    }
    handle @navidrome_api {
      ${streamingBackend port}
    }
    handle {
      import sso_auth
      ${streamingBackend port}
    }
  '';

  # Vaultwarden ab v1.29+: WebSockets laufen über denselben Socket wie der Haupt-HTTP-Server.
  # Kein separater WebSocket-Port mehr — upstream ist entweder unix/... oder 127.0.0.1:PORT.
  genVaultwardenVhost = upstream: ''
    import security_headers
    import upstream_errors
    reverse_proxy ${upstream}
  '';

  genSecurityOnlyVhost = upstream: ''
    ${l7GuardImports}
    import security_headers
    import upstream_errors
    reverse_proxy ${upstream}
  '';

  genZoneVhost =
    {
      zone,
      upstream,
      ...
    }:
    if zone == "internal" then
      ''
        import private_admin
        import security_headers
        import upstream_errors
        reverse_proxy ${upstream}
      ''
    else if zone == "external" then
      ''
        ${l7GuardImports}
        import security_headers
        import sso_auth
        import sso_redirect
        import upstream_errors
        reverse_proxy ${upstream}
      ''
    else if zone == "streaming" then
      ''
        ${l7GuardImports}
        import streamer_headers
        import security_headers
        import sso_auth
        import sso_redirect
        import upstream_errors
        reverse_proxy ${upstream} {
          flush_interval -1
          transport http {
            read_buffer 0
            keepalive off
          }
        }
      ''
    else
      throw "caddy-ingress: zone '${zone}' hat keinen Ingress";

  genHostExtra =
    {
      name,
      entry,
      upstream,
    }:
    if name == "pocket-id" then
      genAuthVhost upstream
    else if name == "jellyfin" then
      genJellyfinVhost entry.port
    else if name == "navidrome" then
      genNavidromeVhost entry.port
    else if name == "vaultwarden" then
      genVaultwardenVhost upstream
    else if name == "homepage" then
      genSecurityOnlyVhost upstream
    else if name == "amp" then
      genSecurityOnlyVhost upstream
    else if
      lib.elem name [
        "home-assistant"
        "zigbee-stack"
      ]
    then
      genSecurityOnlyVhost upstream
    else
      genZoneVhost {
        inherit (entry) zone;
        inherit upstream;
      };

  genVirtualHosts =
    {
      spec,
      domain,
      isEnabled,
    }:
    let
      ingress = lib.filterAttrs (
        name: entry: (entry.subdomain or null) != null && (entry.zone != "loopback") && isEnabled name
      ) spec;

      mkHost =
        name: entry:
        let
          upstream = vpnUpstream name entry;
          fqdn = mkFqdn domain entry;
          extraConfig = genHostExtra {
            inherit name entry upstream;
          };
        in
        lib.nameValuePair fqdn { inherit extraConfig; };
    in
    lib.listToAttrs (lib.mapAttrsToList mkHost ingress);
in
{
  inherit genSecurityOnlyVhost genVirtualHosts;
}

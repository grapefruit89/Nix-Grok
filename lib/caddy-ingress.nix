# ---
# meta:
#   id: NIXH-05-LIB-010
#   layer: 5
#   role: lib
#   purpose: Caddy vHost-Generator aus my.services.spec (Zonen-Policy)
#   docs:
#     - docs/ROADMAP.md
#   tags:
#     - caddy
#     - ingress
# ---
{
  lib,
  caddy,
  vpnConn ? null,
}:
let
  inherit (caddy) streamingBackend;

  vpnUpstream =
    name: entry:
    if vpnConn == null then
      mkUpstream entry
    else if
      lib.elem name [
        "sabnzbd"
        "prowlarr"
      ]
    then
      "${vpnConn.connectionAddress vpnConn.cfg name}:${toString entry.port}"
    else
      mkUpstream entry;

  mkUpstream =
    entry:
    if entry.socket or null != null then "unix/${entry.socket}" else "127.0.0.1:${toString entry.port}";

  mkFqdn = domain: entry: "${entry.subdomain}.${domain}";

  genAuthVhost = upstream: ''
    import security_headers
    handle /api/auth/* {
      reverse_proxy ${upstream}
    }
    handle /.well-known/* {
      reverse_proxy ${upstream}
    }
    handle /admin/* {
      import tailscale_admin
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

    @jellyfin_client header_regexp X-Emby-Authorization (?i)MediaBrowser

    handle @jellyfin_client {
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

  genVaultwardenVhost = port: ''
    import security_headers

    @websocket {
      header Connection *Upgrade*
      header Upgrade websocket
    }
    handle @websocket {
      reverse_proxy 127.0.0.1:${toString (port + 1)}
    }
    reverse_proxy 127.0.0.1:${toString port}
  '';

  genSecurityOnlyVhost = upstream: ''
    import security_headers
    reverse_proxy ${upstream}
  '';

  genZoneVhost =
    {
      zone,
      upstream,
      subdomain,
    }:
    if zone == "admin-hangar" then
      ''
        import tailscale_admin
        import security_headers
        reverse_proxy ${upstream}
      ''
    else if zone == "public" then
      ''
        import security_headers
        reverse_proxy ${upstream}
      ''
    else if zone == "family-pocketid" && lib.elem subdomain streamingSubdomains then
      ''
        import streamer_headers
        import security_headers
        import sso_auth
        reverse_proxy ${upstream} {
          flush_interval -1
          transport http {
            read_buffer 0
            keepalive off
          }
        }
      ''
    else if zone == "family-pocketid" then
      ''
        import security_headers
        import sso_auth
        reverse_proxy ${upstream}
      ''
    else
      throw "caddy-ingress: zone '${zone}' hat keinen Ingress";

  streamingSubdomains = [
    "audiobookshelf"
  ];

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
      genVaultwardenVhost entry.port
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
        inherit (entry) subdomain;
      };

  genVirtualHosts =
    {
      spec,
      domain,
      isEnabled,
      blockyMetricsPort,
    }:
    let
      ingress = lib.filterAttrs (
        name: entry: (entry.subdomain or null) != null && (entry.zone != "loopback") && isEnabled name
      ) spec;

      mkHost =
        name: entry:
        let
          upstream =
            if name == "blocky" then "127.0.0.1:${toString blockyMetricsPort}" else vpnUpstream name entry;
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
  inherit genVirtualHosts streamingSubdomains;
}

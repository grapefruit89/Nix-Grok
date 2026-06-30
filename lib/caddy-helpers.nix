# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Caddy vHost-Helfer — Proxy, SSO, Unix-Socket-Upstreams
#   tags:
#     - caddy
#     - ingress
# ---
{ lib }:
let
  upstream = host: port: "${host}:${toString port}";

  mkProxy =
    {
      port,
      host ? "127.0.0.1",
      imports ? [ ],
    }:
    lib.concatStringsSep "\n" (
      map (snippet: "import ${snippet}") imports
      ++ [
        "request_body { max_size 100MB }"
        "reverse_proxy ${upstream host port}"
      ]
    );

  mkProxyUnix =
    {
      socketPath,
      imports ? [ ],
    }:
    let
      sockets = import ./unix-sockets.nix { inherit lib; };
    in
    lib.concatStringsSep "\n" (
      map (snippet: "import ${snippet}") imports
      ++ [
        "request_body { max_size 100MB }"
        "reverse_proxy ${sockets.toCaddyUpstream socketPath}"
      ]
    );

  streamingBackend = port: ''
    reverse_proxy ${upstream "127.0.0.1" port} {
      flush_interval -1
      transport http {
        read_buffer 0
        keepalive off
      }
    }
  '';
in
{
  inherit mkProxy streamingBackend;

  proxySso =
    port:
    mkProxy {
      inherit port;
      imports = [ "sso_auth" ];
    };

  proxyPrivateSso =
    {
      port,
      host ? "127.0.0.1",
    }:
    mkProxy {
      inherit port host;
      imports = [
        "private_admin"
        "sso_auth"
      ];
    };

  proxySecurity =
    port:
    mkProxy {
      inherit port;
      imports = [ "security_headers" ];
    };

  proxyDirect = port: mkProxy { inherit port; };

  proxyUnixSso =
    socketPath:
    mkProxyUnix {
      inherit socketPath;
      imports = [ "sso_auth" ];
    };

  proxyUnixPrivateSso =
    socketPath:
    mkProxyUnix {
      inherit socketPath;
      imports = [
        "private_admin"
        "sso_auth"
      ];
    };

  proxyUnixSecurity =
    socketPath:
    mkProxyUnix {
      inherit socketPath;
      imports = [ "security_headers" ];
    };

  proxyUnixDirect =
    socketPath:
    mkProxyUnix {
      inherit socketPath;
      imports = [ ];
    };
}

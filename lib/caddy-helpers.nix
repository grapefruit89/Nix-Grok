# Caddy vHost-Bausteine — eine Funktion, Snippet-Imports als Liste.
{ lib }:

let
  upstream = host: port: "${host}:${toString port}";

  mkProxy =
    { port
    , host ? "127.0.0.1"
    , imports ? [ ]
    ,
    }:
    lib.concatStringsSep "\n" (
      map (snippet: "import ${snippet}") imports
      ++ [ "reverse_proxy ${upstream host port}" ]
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

  proxySso = port: mkProxy { inherit port; imports = [ "sso_auth" ]; };

  proxySsoBypassApp = port: mkProxy { inherit port; imports = [ "sso_auth_bypass" ]; };

  proxyTailscaleSso = port:
    mkProxy {
      inherit port;
      imports = [ "tailscale_admin" "sso_auth" ];
    };

  proxySecurity = port: mkProxy { inherit port; imports = [ "security_headers" ]; };

  proxyDirect = port: mkProxy { inherit port; };
}

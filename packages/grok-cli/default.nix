{ stdenv, lib }: stdenv.mkDerivation { pname = "grok-cli"; version = "1.0"; src = ./.; installPhase = "mkdir -p $out/bin && echo 'echo dummy' > $out/bin/grok-cli && chmod +x $out/bin/grok-cli"; }

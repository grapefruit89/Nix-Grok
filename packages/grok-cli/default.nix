# ---
# meta:
#   role: package
#   purpose: Gepinnte xAI Grok Build CLI als Nix-Derivation
#   tags:
#     - grok
#     - package
# ---
{
  lib,
  stdenv,
  fetchurl,
}:

let
  version = "0.2.51";
in
stdenv.mkDerivation {
  pname = "grok-cli";
  inherit version;

  src = fetchurl {
    url = "https://x.ai/cli/grok-${version}-linux-x86_64";
    hash = "sha256-UpFiZ6oveGjCOm3XhH3+Bm45pSuP/SFjgBhjl+p9AHU=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/grok
    ln -s grok $out/bin/agent
    runHook postInstall
  '';

  meta = with lib; {
    description = "Grok Build CLI (xAI) — pinned upstream binary";
    homepage = "https://x.ai/cli";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "grok";
  };
}

# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Wartet auf HTTP-API (nixarr waitForService / nixflix mkWaitForApiScript)
#   tags:
#     - media
#     - api
# ---
{
  lib,
  pkgs,
}: {
  mkScript = {
    name,
    url,
    maxAttempts ? 30,
    sleepSeconds ? 2,
    requireFail ? false,
  }:
    pkgs.writeShellScript "wait-for-${name}" ''
      set -euo pipefail
      echo "Waiting for ${name} at '${url}'..."
      for i in $(seq 1 ${toString maxAttempts}); do
        if ${pkgs.curl}/bin/curl \
            --silent \
            ${lib.optionalString requireFail "--fail"} \
            --max-time 5 \
            --output /dev/null \
            '${url}'; then
          echo "${name} is available"
          exit 0
        fi
        sleep ${toString sleepSeconds}
      done
      echo "${name} not available after ${toString maxAttempts} attempts" >&2
      exit 1
    '';
}

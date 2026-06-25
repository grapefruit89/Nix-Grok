# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Locale, Zeitzone, Sprache für moritz
#   tags:
#     - locale
# ---
{ config, lib, pkgs, ... }:

{
  my.configs.locale = {
    default = "de_DE.UTF-8";
    language = "de";
    timezone = "Europe/Berlin";
  };
}
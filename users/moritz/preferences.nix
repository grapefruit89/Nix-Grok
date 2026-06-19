# preferences.nix
# Centralized language, locale, and timezone settings for user moritz.
# All system modules and user environments derive their settings from here.

{
  ...
}:

{
  my.configs.locale = {
    default = "de_DE.UTF-8";
    language = "de";
    timezone = "Europe/Berlin";
  };
}

{
  config,
  lib,
  pkgs,
  grok-cli ? null,
  ...
}:

let
  cfg = config.my.services.grok;
  package =
    if cfg.package != null then
      cfg.package
    else
      (if grok-cli != null then grok-cli else pkgs.callPackage ../../packages/grok-cli { });
  inherit (cfg) user;
  group = config.users.users.${user}.group or "users";
  stateDir = cfg.stateDirectory;
  binDir = "${stateDir}/bin";
in
{
  options.my.services.grok = {
    enable = lib.mkEnableOption "Grok Build CLI (xAI) for headless SSH workflows";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Pinned Grok CLI derivation. Defaults to packages/grok-cli.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.my.configs.identity.user;
      description = "POSIX user that owns Grok state and runs the CLI.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${config.my.configs.identity.user}/.grok";
      description = "Persistent Grok state (auth, sessions, config, completions).";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional XAI API key file for headless auth (SOPS later).";
    };

    headless = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Headless SSH defaults (no auto-update, store-linked binary).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0700 ${user} ${group} -"
      "d ${stateDir}/sessions 0700 ${user} ${group} -"
      "d ${stateDir}/completions 0755 ${user} ${group} -"
      "d ${stateDir}/completions/bash 0755 ${user} ${group} -"
      "d ${stateDir}/completions/zsh 0755 ${user} ${group} -"
      "d ${binDir} 0755 ${user} ${group} -"
    ];

    system.activationScripts.grok-cli = ''
      install -d -o ${user} -g ${group} -m 0700 ${stateDir}
      install -d -o ${user} -g ${group} -m 0700 ${stateDir}/sessions
      install -d -o ${user} -g ${group} -m 0755 ${stateDir}/completions/bash
      install -d -o ${user} -g ${group} -m 0755 ${stateDir}/completions/zsh
      install -d -o ${user} -g ${group} -m 0755 ${binDir}
      ln -sfn ${package}/bin/grok ${binDir}/grok
      ln -sfn ${package}/bin/agent ${binDir}/agent
      chown -R ${user}:${group} ${stateDir}
    '';

    environment.systemPackages = [ package ];
  };
}

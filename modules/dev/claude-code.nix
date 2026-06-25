# ---
# meta:
#   layer: 4
#   role: module
#   purpose: Claude Code CLI (Anthropic) als System-Paket
#   tags:
#     - dev
#     - claude
# ---
{ config, pkgs, lib, claude-code-pkg ? null, ... }:

{
  options.services.claude-code.enable = lib.mkEnableOption "Claude Code CLI (Anthropic)";

  config = lib.mkIf config.services.claude-code.enable {
    environment.systemPackages = [
      (if claude-code-pkg != null then claude-code-pkg else pkgs.claude-code)
    ];
  };
}

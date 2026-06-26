# ---
# meta:
#   layer: 1
#   role: flake
#   purpose: Flake-Inputs und NixOS-Output q958 inkl. Pakete
#   tags:
#     - flake
#     - entrypoint
# ---
{
  description = "NixOS Configuration — Fujitsu Q958 Homelab Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      impermanence,
      home-manager,
      hermes-agent,
      sops-nix,
      llm-agents,
      mcp-servers-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      grok-cli = pkgs.callPackage ./packages/grok-cli { };
      claude-code-pkg = llm-agents.packages.${system}.claude-code;
      mcpConfigFile = mcp-servers-nix.lib.mkConfig pkgs {
        format = "json";
        programs.context7 = {
          enable = true;
          envFile = "/var/lib/secrets/context7.env";
        };
        programs.nixos.enable = true;
      };
    in
    {
      packages.${system}.grok-cli = grok-cli;

      nixosConfigurations = {
        q958 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              grok-cli
              claude-code-pkg
              mcpConfigFile
              ;
          };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ./machines/q958/default.nix
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
            hermes-agent.nixosModules.default
            sops-nix.nixosModules.sops
          ];
        };
      };
    };
}

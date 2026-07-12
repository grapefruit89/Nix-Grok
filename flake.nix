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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
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
      llm-agents,
      disko,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      grok-cli = pkgs.callPackage ./packages/grok-cli { };
      secrets-portal = pkgs.callPackage ./packages/secrets-portal { };
      arr-provision = pkgs.callPackage ./packages/arr-provision { };
      claude-code-pkg = llm-agents.packages.${system}.claude-code;
    in
    {
      packages.${system} = {
        inherit grok-cli;
        inherit secrets-portal;
        inherit arr-provision;
        # Lokale Optionsreferenz: `nix build .#docs && cat result`
        # Generiert JSON-Dokumentation aller my.* Optionen aus dem evaluierten q958-System.
        # Benötigt profile.local.nix (secrets). Nur auf dem Host sinnvoll nutzbar.
        docs =
          (pkgs.nixosOptionsDoc {
            options = self.nixosConfigurations.q958.options.my;
          }).optionsJSON;
      };

      diskoConfigurations.q958 = import ./machines/q958/disko.nix;

      # Lern-VM: disko destroy/format/mount sicher in QEMU (kein profile.local nötig)
      diskoConfigurations.q958-disko-vm = import ./machines/q958/disko-vm.nix;

      nixosConfigurations = {
        q958 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              grok-cli
              claude-code-pkg
              disko
              ;
          };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ./machines/q958/default.nix
            ./machines/q958/disko-enabled.nix
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
            hermes-agent.nixosModules.default
          ];
        };

        q958-disko-vm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./machines/q958/disko-vm.nix
            ./machines/q958/disko-vm-minimal.nix
          ];
        };
      };
    };
}

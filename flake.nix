{
  description = "Cranky's NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixvim, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      homeModules = [
        nixvim.homeModules.nixvim
        ./home-modules/init.nix
      ];
    in
    {
      # Full rebuilds apply the same home configuration used by home.sh.
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              backupFileExtension = "backup";
              users.cranky.imports = homeModules;
            };
            # Keep the standalone testing command available after a full rebuild.
            environment.systemPackages = [ home-manager.packages.${system}.home-manager ];
          }
        ];
      };

      homeConfigurations = {
        "cranky" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = homeModules;
        };
      };
    };
}


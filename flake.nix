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

  outputs = { self, nixpkgs, home-manager, nixvim, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [

            ./configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.users.cranky = {
                imports = [
                  nixvim.homeModules.nixvim

                  
                  ./home-modules/init.nix
                ];
              };
            }
          ];
        };
      };

      homeConfigurations = {
        "cranky" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            nixvim.homeModules.nixvim
            ./home-modules/init.nix
          ];
        };
      };
    };
}


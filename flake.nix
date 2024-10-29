{
  description = "My Nix configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    #nixarr.url = "github:rasmus-kirk/nixarr/dev";
    #nixarr.inputs.nixpkgs.follows = "nixpkgs";

    vpn-confinement.url = "github:rasmus-kirk/VPN-Confinement";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    agenix,
    #nixarr,
    vpn-confinement,
    home-manager,
    nixos-hardware,
    ...
  }:
    let
      # Systems supported
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      # Helper to provide system-specific attributes
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in {
      nixosModules = rec {
        kirk = import ./modules/nixos;
        default = kirk;
      };
      homeManagerModules = rec {
        kirk = import ./modules/home-manager;
        default = kirk;
      };
      devShells = forAllSystems ({ pkgs } : {
        default = pkgs.mkShell {
          packages = with pkgs; [
            alejandra
            nixd
          ];
        };
      });
      packages = forAllSystems ({ pkgs } : {
        default = pkgs.callPackage ./docs/mkDocs.nix {inherit inputs;};
      });
      formatter = forAllSystems ({ pkgs }: pkgs.alejandra);
      nixosConfigurations = {
        pi = nixpkgs.lib.nixosSystem rec {
          system = "aarch64-linux";

          modules = [
            ./configurations/nixos/pi/configuration.nix
            agenix.nixosModules.default
            nixos-hardware.nixosModules.raspberry-pi-4
            self.nixosModules.default
            #nixarr.nixosModules.default
            vpn-confinement.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.users.user = {
                imports = [
                  ./configurations/home-manager/pi/home.nix
                  self.homeManagerModules.default
                ];
                config.home.packages = [home-manager.packages."${system}".default];
              };
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];

          specialArgs = {inherit inputs;};
        };
      };
      homeConfigurations = {
        work = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };

          modules = [
            ./configurations/home-manager/work/home.nix
            self.homeManagerModules.default
          ];
        };

        deck = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };

          modules = [
            ./configurations/home-manager/deck/home.nix
            self.homeManagerModules.default
          ];
        };
      };
    };
}

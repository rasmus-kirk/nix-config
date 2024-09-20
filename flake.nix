{
  description = "My Nixos configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    nixarr.url = "github:rasmus-kirk/nixarr/dev";
    nixarr.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Flake stuff
    flake-root.url = "github:srid/flake-root";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    agenix,
    nixarr,
    home-manager,
    nixos-hardware,
    flake-parts,
    flake-root,
    ...
  }:
    flake-parts.lib.mkFlake {
      inherit inputs;
    } {
      imports = with inputs; [
        flake-root.flakeModule
        treefmt-nix.flakeModule
        devshell.flakeModule
      ];
      flake = {
        nixosModules = rec {
          kirk = import ./modules/nixos;
          default = kirk;
        };
        homeManagerModules = rec {
          kirk = import ./modules/home-manager;
          default = kirk;
        };
        nixosConfigurations = {
          pi = nixpkgs.lib.nixosSystem rec {
            system = "aarch64-linux";

            modules = [
              ./configurations/nixos/pi/configuration.nix
              agenix.nixosModules.default
              nixos-hardware.nixosModules.raspberry-pi-4
              self.nixosModules.default
              nixarr.nixosModules.default
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

          pi = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-linux";
              config.allowUnfree = true;
            };

            modules = [
              ./configurations/home-manager/pi/home.nix
              self.homeManagerModules.default
            ];
          };
        };
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem = {
        config,
        pkgs,
        ...
      }: {
        treefmt.config = {
          inherit (config.flake-root) projectRootFile;
          package = pkgs.treefmt;

          programs = {
            alejandra.enable = true;
            deadnix.enable = true;
          };
        };

        packages = rec {
          docs = pkgs.callPackage ./docs/mkDocs.nix {inherit inputs;};
          default = docs;
        };

        devshells.default = {
          name = "Default";

          commands = [
            {
              category = "Tools";
              name = "fmt";
              help = "Format the source tree";
              command = "nix fmt";
            }
          ];
        };
      };
    };
}

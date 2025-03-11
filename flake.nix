{
  description = "My Nix configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    nixarr.url = "github:rasmus-kirk/nixarr/dev";
    nixarr.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    website-builder.url = "github:rasmus-kirk/website-builder";
    website-builder.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    agenix,
    nixarr,
    home-manager,
    nixos-hardware,
    website-builder,
    nix-index-database,
    ...
  }: let
    # Systems supported
    supportedSystems = [
      "x86_64-linux" # 64-bit Intel/AMD Linux
      "aarch64-linux" # 64-bit ARM Linux
      "x86_64-darwin" # 64-bit Intel macOS
      "aarch64-darwin" # 64-bit ARM macOS
    ];

    # Helper to provide system-specific attributes
    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          pkgs = import nixpkgs {inherit system;};
        });
  in {
    nixosModules.default = import ./modules/nixos;

    homeManagerModules.default = {
      imports = [./modules/home-manager];
      config._module.args = {inherit inputs;};
    };

    devShells = forAllSystems ({pkgs}: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          nixd
        ];
      };
    });

    packages = forAllSystems ({pkgs}: let
      website = website-builder.lib {
        pkgs = pkgs;
        src = ./.;
        timestamp = self.lastModified;
        headerTitle = "Rasmus Kirk";
        standalonePages = [
          {
            inputFile = ./docs/index.md;
            title = "Kirk Modules - Option Documentation";
          }
        ];
        navbar = [
          {
            title = "Home";
            location = "/";
          }
          {
            title = "Nixos";
            location = "/nixos-options";
          }
          {
            title = "Home Manager";
            location = "/home-manager-options";
          }
          {
            title = "Github";
            location = "https://github.com/rasmus-kirk/nix-config";
          }
        ];
        homemanagerModules = ./modules/home-manager;
        nixosModules = ./modules/nixos;
      };
    in {
      default = website.package;
      debug = website.loop;
    });

    formatter = forAllSystems ({pkgs}: pkgs.alejandra);

    nixosConfigurations = {
      server = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";

        modules = [
          ./configurations/nixos/server/configuration.nix
          agenix.nixosModules.default
          self.nixosModules.default
          nixarr.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.users.user = {
              imports = [
                ./configurations/home-manager/server/home.nix
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
          nix-index-database.hmModules.nix-index
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
          nix-index-database.hmModules.nix-index
          self.homeManagerModules.default
        ];
      };
    };
  };
}

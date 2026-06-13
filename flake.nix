{
  description = "My Nix configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    nixarr.url = "github:nix-media-server/nixarr/kirk/1984";
    nixarr.inputs.nixpkgs.follows = "nixpkgs";
    nixarr.inputs.vpnconfinement.follows = "nixpkgs";

    vpnconfinement.url = "github:Maroka-chan/VPN-Confinement";

    hosts.url = "github:StevenBlack/hosts";
    hosts.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";

    website-builder.url = "github:rasmus-kirk/website-builder";
    website-builder.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    jovian.url = "github:Jovian-Experiments/Jovian-NixOS";
    jovian.inputs.nixpkgs.follows = "nixpkgs";

    keyboard-layout.url = "github:rasmus-kirk/keyboard-layout";
    keyboard-layout.inputs.nixpkgs.follows = "nixpkgs";

    rustle.url = "github:rasmus-kirk/rustle";
    rustle.inputs.nixpkgs.follows = "nixpkgs";

    submerger.url = "github:rasmus-kirk/submerger";
    submerger.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    # Private game source — github.com/rasmus-kirk/ballbrawl (private repo).
    # Fetched over SSH using the YubiKey-SK key at `nix flake update` time;
    # flake.lock pins the rev so normal builds don't re-fetch.
    ballbrawl = {
      url = "git+ssh://git@github.com/rasmus-kirk/ballbrawl.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    agenix,
    nixarr,
    jovian,
    home-manager,
    website-builder,
    vpnconfinement,
    hosts,
    nix-index-database,
    impermanence,
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
          cargo
          rustc
          rustfmt
          clippy
          rust-analyzer
        ];
      };
    });

    packages = forAllSystems ({pkgs}: let
      website = website-builder.lib {
        pkgs = pkgs;
        src = self;
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
      box-broker = pkgs.rustPlatform.buildRustPackage {
        pname = "box-broker";
        version = "0.2.0";
        src = ./modules/home-manager/box/packages/box-broker;
        cargoLock.lockFile = ./modules/home-manager/box/packages/box-broker/Cargo.lock;
      };
      box-approver = pkgs.rustPlatform.buildRustPackage {
        pname = "box-approver";
        version = "0.2.0";
        src = ./modules/home-manager/box/packages/box-broker;
        cargoLock.lockFile = ./modules/home-manager/box/packages/box-broker/Cargo.lock;
      };
    });

    formatter = forAllSystems ({pkgs}: pkgs.alejandra);

    nixosConfigurations = {
      desktop = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";

        modules = [
          ./configurations/nixos/desktop/configuration.nix
          agenix.nixosModules.default
          self.nixosModules.default
          nixarr.nixosModules.default
          impermanence.nixosModules.impermanence
          jovian.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.users.user = {
              imports = [
                ./configurations/home-manager/desktop/home.nix
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

      deck-oled = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";

        modules = [
          ./configurations/nixos/deck-oled/configuration.nix
          agenix.nixosModules.default
          self.nixosModules.default
          jovian.nixosModules.default
          vpnconfinement.nixosModules.default
          home-manager.nixosModules.home-manager
          hosts.nixosModule
          {
            networking.stevenBlackHosts = {
              enable = true;
              enableIPv6 = true;
              blockFakenews = true;
              blockGambling = true;
              blockPorn = true;
              blockSocial = true;
            };
          }
          {
            home-manager.users.user = {
              imports = [
                ./configurations/home-manager/deck-oled/home.nix
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

      work = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";

        modules = [
          ./configurations/nixos/work/configuration.nix
          agenix.nixosModules.default
          self.nixosModules.default
          # nix-index-database.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.users.user = {
              imports = [
                ./configurations/home-manager/work/home.nix
                self.homeManagerModules.default
                nix-index-database.homeModules.nix-index
              ];
              config.home.packages = [home-manager.packages."${system}".default];
            };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
          }
          hosts.nixosModule
          {
            networking.stevenBlackHosts = {
              enable = true;
              enableIPv6 = true;
              blockFakenews = true;
              blockGambling = true;
              blockPorn = true;
              blockSocial = true;
            };
          }
        ];

        specialArgs = {inherit inputs;};
      };
    };

    homeConfigurations = {
      sandbox = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };

        extraSpecialArgs = {inherit inputs;};

        modules = [
          ./configurations/home-manager/sandbox/home.nix
          # nix-index-database.homeModules.nix-index
          self.homeManagerModules.default
        ];
      };

      naja-deck = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };

        extraSpecialArgs = {inherit inputs;};

        modules = [
          ./configurations/home-manager/naja-deck/home.nix
          nix-index-database.homeModules.nix-index
          self.homeManagerModules.default
        ];
      };
    };
  };
}

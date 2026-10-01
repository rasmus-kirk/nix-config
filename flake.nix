{
  description = "My Nix configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    nixarr.url = "github:nix-media-server/nixarr";
    nixarr.inputs.nixpkgs.follows = "nixpkgs";
    nixarr.inputs.vpnconfinement.follows = "vpnconfinement";

    vpnconfinement.url = "github:Maroka-chan/VPN-Confinement";

    hosts.url = "github:StevenBlack/hosts";
    hosts.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    website-builder.url = "github:rasmus-kirk/website-builder";
    website-builder.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    jovian.url = "github:Jovian-Experiments/Jovian-NixOS";
    jovian.inputs.nixpkgs.follows = "nixpkgs";

    keyboard-layout.url = "github:rasmus-kirk/keyboard-layout";
    keyboard-layout.inputs.nixpkgs.follows = "nixpkgs";

    submerger.url = "github:rasmus-kirk/submerger";
    submerger.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
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

    mkSandbox = boxUser:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };

        extraSpecialArgs = {inherit inputs boxUser;};

        modules = [
          ./configurations/home-manager/sandbox/home.nix
          self.homeManagerModules.default
        ];
      };
  in {
    nixosModules.default = {
      imports = [
        ./modules/nixos
        hosts.nixosModule
      ];
    };

    homeManagerModules.default = {
      imports = [
        ./modules/home-manager
        nix-index-database.homeModules.nix-index
      ];
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
      ssh-bootstrap = pkgs.callPackage ./ssh-keys/bootstrap.nix {};
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
            home-manager.users.steam = {
              imports = [
                ./configurations/home-manager/desktop-steam/home.nix
                self.homeManagerModules.default
              ];
            };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
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
          home-manager.nixosModules.home-manager
          {
            home-manager.users.user = {
              imports = [
                ./configurations/home-manager/work/home.nix
                self.homeManagerModules.default
              ];
              config.home.packages = [home-manager.packages."${system}".default];
            };
            home-manager.users.dev = {
              imports = [
                ./configurations/home-manager/dev/home.nix
                self.homeManagerModules.default
              ];
              config.home.packages = [home-manager.packages."${system}".default];
            };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
          }
        ];

        specialArgs = {inherit inputs;};
      };
    };

    homeConfigurations = {
      sandbox = mkSandbox "user";
      sandbox-dev = mkSandbox "dev";

      naja-deck = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };

        extraSpecialArgs = {inherit inputs;};

        modules = [
          ./configurations/home-manager/naja-deck/home.nix
          self.homeManagerModules.default
        ];
      };
    };
  };
}

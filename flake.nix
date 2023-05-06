{
	description = "Home Manager configuration of user";

	inputs = {
		# Specify the source of Home Manager and Nixpkgs.
		nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
		home-manager = {
			url = "github:rasmus-kirk/home-manager";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		agenix = {
			url = "github:ryantm/agenix";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		nixos-hardware.url = "github:NixOS/nixos-hardware/master";
	};

	outputs = { nixpkgs, home-manager, agenix, nixos-hardware, ... }: {
		nixosConfigurations = {
			pi = nixpkgs.lib.nixosSystem {
				system = "aarch64-linux";

				modules = [
					./system/pi/configuration.nix
					agenix.nixosModules.default
					nixos-hardware.nixosModules.raspberry-pi-4
					home-manager.nixosModules.home-manager
					{
						home-manager.useGlobalPkgs = true;
						home-manager.useUserPackages = true;
						home-manager.users.user = import ./home-manager/pi/home.nix;
					}
				];
			};
		};

		homeConfigurations."work" = home-manager.lib.homeManagerConfiguration {
			pkgs = import nixpkgs {
				system = "x86_64-linux";
				config.allowUnfree = true;
			};        

			modules = [ 
				./home-manager/work/home.nix
				./modules/home-manager
			];
		};

		homeConfigurations."pi" = home-manager.lib.homeManagerConfiguration {
			pkgs = import nixpkgs {
				system = "x86_64-linux";
				config.allowUnfree = true;
			};        

			modules = [ 
				./home-manager/pi/home.nix
				./modules/home-manager
			];
		};
	};
}

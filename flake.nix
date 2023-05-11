{
	description = "Home Manager configuration of rasmus-kirk";

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

	outputs = { nixpkgs, agenix, home-manager, nixos-hardware, ... }@inputs: {
		nixosConfigurations = {
			pi = nixpkgs.lib.nixosSystem {
				system = "aarch64-linux";

				modules = [
					./nixos/pi/configuration.nix
					agenix.nixosModules.default
					nixos-hardware.nixosModules.raspberry-pi-4
				];

				specialArgs = { inherit inputs; };
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
				system = "aarch64-linux";
				config.allowUnfree = true;
			};

			modules = [ 
				./home-manager/pi/home.nix
				./modules/home-manager
			];
		};
	};
}

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

	outputs = { nixpkgs, agenix, home-manager, nixos-hardware, ... }@inputs: 
		let colorscheme = {
			# Gruvbox theme colors
				bg = "282828";
				fg = "ebdbb2";

				black  = "1d2021";
				white  = "d5c4a1";
				orange = "d65d0e";
				red    = "cc241d";
				green  = "98971a";
				yellow = "d79921";
				blue   = "458588";
				purple = "b16286";
				teal   = "689d6a";

				bright = {
					black  = "928374";
					white  = "fbf1c7";
					orange = "fe8019";
					red    = "fb4934";
					green  = "b8bb26";
					yellow = "fabd2f";
					blue   = "83a598";
					purple = "d3869b";
					teal   = "8ec07c";
				};
			};
		in {
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
					colorscheme
				];
			};

			homeConfigurations."pi" = home-manager.lib.homeManagerConfiguration {
				pkgs = import nixpkgs {
					system = "aarch64-linux";
					config.allowUnfree = true;
				};

				inherit colorscheme;

				modules = [ 
					./home-manager/pi/home.nix
					./modules/home-manager
				];
			};
	};
}

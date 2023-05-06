{
  description = "Home Manager configuration of user";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:rasmus-kirk/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    {
      homeConfigurations."user" = let 
        system = "x86_64-linux";
      in home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };        

        modules = [ 
          ./home-manager/work/home.nix
          ./modules/home-manager
        ];
      };
    };
}

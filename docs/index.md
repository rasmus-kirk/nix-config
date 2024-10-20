This is the options documentation for my personal nix modules

- **Docs for the home manager modules** can be found [here](./home.html)
- **Docs for the nixos modules** can be found [here](./nixos.html)

### Importing Modules

The options I’ve created allow for different behaviors across devices, while
avoiding redundant configuration snippets. Although these modules are designed
for personal use, it's possible for others to reuse them:

```nix
{
  description = "My Nixos configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    kirk-modules.url = "github:rasmus-kirk/nix-config";
    kirk-modules.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    kirk-modules,
    flake-parts,
    ...
  }: let
    inherit (self) outputs;
  in {
    homeConfigurations = {
      myMachine = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {inherit inputs outputs;};
        modules = [
          ./configurations/home-manager/my-machine/home.nix
          kirk-modules.homeManagerModules.default
        ];
      };
    };
  };
}
```


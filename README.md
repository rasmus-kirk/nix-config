# My nix config

Repo for my nix config.

- `configurations/home-manager`:
  - Home-Manager configurations for my machines (deck, pi, and work).
- `configurations/nixos`
  - Nixos configurations for my machines (pi).
- `modules/home-manager`
  - Home Manager modules generalizing configuration for various tools.
- `modules/home-manager`
  - Nixos modules generalizing configuration for various tools.
- `pubkeys`
  - Public keys for my machines
- `docs`
  - The necessary files for building the documentation at [https://nix.rasmuskirk.com/](https://nix.rasmuskirk.com/)

## The Configurations

TODO!

## The Modules

The modules allow configuration to be reused efficiently and without
duplication between machines. For example, I want to share configuration
between my Pi-based nas and my work laptop such as editor, file manager,
git, shell and more.

Example follows below:

### Snippet from Work Laptop's Configuration

```nix
  kirk = {
    fonts.enable = true;
    foot.enable = true;
    fzf.enable = true;
    git = { enable = true; userEmail = "mail@rasmuskirk.com"; userName = "rasmus-kirk"; };
    helix.enable = true;
    homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
    jiten.enable = true;
    joshuto.enableZshIntegration = false;
    kakoune.enable = true;
    scripts.enable = true;
    ssh = { enable = true; identityPath = "${secretDir}/id_ed25519"; };
    terminalTools.enable = true;
    userDirs = { enable = true; autoSortDownloads = true; };
    yazi = { enable = true; configDir = configDir; };
    zathura = { enable = true; darkmode = false; };
    zsh.enable = true;
  };
```

### Snippet from Nas/Pi's Configuration

```nix
  kirk = {
    terminalTools.enable = true;
    fzf.enable = true;
    git = { enable = true; userEmail = "mail@rasmuskirk.com"; userName = "rasmus-kirk"; };
    helix = { enable = true; installMostLsps = false; extraPackages = with pkgs; [nil marksman nodePackages_latest.bash-language-server]; };
    homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
    userDirs = { enable = true; autoSortDownloads = true; };
    yazi = { enable = true; configDir = configDir; };
    kakoune.enable = true;
    ssh = { enable = true; identityPath = "${secretDir}/${machine}/ssh/id_ed25519"; };
    zsh.enable = true;
    fonts.enable = true;
  };
```

### Importing Modules

The options that I have created allows varying behaviour between machines,
while keeping configuration duplication low. Even though the modules are
created and maintained for personal use the flake allows others to reuse
the modules if they so please.

```nix
{
  description = "My Nixos configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    kirk-modules.url = "github:rasmus-kirk/nixarr/nix-configuration";
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

### Automatically generated module documentation

The nix modules have built-in compilation of module options to markdown. I
leverage this and compile that markdown further into html using pandoc. This
pandoc, can then be deployed using Github Pages. The website containing the
module documentation can be found [here](https://nix.rasmuskirk.com/). See
`./docs` for more details.

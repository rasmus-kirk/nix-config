# My Nix Config

This repository contains my Nix configurations. Feel free to explore and
use any part that inspires you.

**Features:**

- Single flake setup
- [Agenix](https://github.com/ryantm/agenix) for secrets management
- Home-Manager integration
- Modularization
- Automatic module options documentation generation at [https://nix.rasmuskirk.com/](https://nix.rasmuskirk.com/)
- NAS setup

**Directions:**

- `configurations/home-manager`:
  - Home-Manager configurations for my devices (deck, NAS, and work) and the bubblewrap sandbox.
- `configurations/nixos`:
  - NixOS configurations for my devices.
- `modules/home-manager`:
  - Home-Manager modules generalizing configuration for various tools.
- `modules/nixos`:
  - NixOS modules generalizing configuration for various tools.
- `ssh-keys`:
  - Public SSH keys. `age/` holds each machine's host key, encrypted to the YubiKey.
- `docs`:
  - Files required for building the documentation hosted at [https://nix.rasmuskirk.com/](https://nix.rasmuskirk.com/).

## The Configurations

The Home-Manager configurations are fairly straightforward since they mostly
reuse modules, but the NixOS configurations have some notable features:

- [Agenix](https://github.com/ryantm/agenix) for secrets management
- [Nixarr](https://nixarr.com/) integration
- Syncthing
- [Jovian](https://github.com/Jovian-Experiments/Jovian-NixOS) Steam game mode
- YubiKey login and sudo

## The Modules

The modules allow configuration to be reused efficiently and without
duplication between machines. For example, I want to share configuration
between my NAS and my work laptop for programs such as my editor,
file manager, git, shell and more.

An example follows below:

### Snippet from Work Laptop's Configuration

```nix
  kirk = {
    helix.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    zsh.enable = true;
    fonts.enable = true;
    terminalTools.enable = true;
  };
```

### Snippet from NAS Configuration

```nix
  kirk = {
    helix.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    zsh = {
      enable = true;
      stateDir = stateDir;
    };
    fonts.enable = true;
    terminalTools.enable = true;
  };
```

### Importing Modules

The options I’ve created allow for different behaviors across devices, while
avoiding redundant configuration snippets. Although these modules are designed
for personal use, it's possible for others to reuse them:

```nix
{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    kirk-modules.url = "github:rasmus-kirk/nix-config";
    kirk-modules.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    kirk-modules,
    home-manager,
    ...
  }: let
    inherit (self) outputs;
  in {
    homeConfigurations = {
      myMachine = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = { inherit inputs outputs; };
        modules = [
          ./configurations/home-manager/my-machine/home.nix
          kirk-modules.homeManagerModules.default
        ];
      };
    };
  };
}
```

### Automatically Generated Module Documentation

The Nix modules include built-in compilation of module options to
Markdown. I further convert this Markdown into HTML using Pandoc, which
is then deployed via GitHub Pages. You can find the module documentation
[here](https://nix.rasmuskirk.com/). For more details, see [this
repo](https://github.com/rasmus-kirk/website-builder).

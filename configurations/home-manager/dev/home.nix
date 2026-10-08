{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  username = "dev";
  homeDir = "/home/${username}";
in {
  kirk = {
    terminalTools.enable = true;
    helix.enable = true;
    podman.enable = true;
    scripts.enable = true;
    jiten.enable = true;
    claudeConfig = {
      enable = true;
      notion.enable = true;
    };
    git = {
      enable = true;
      signKey = "/run/dev-secret/ssh/id_ed25519_yubi.pub";
      signPubKey = ../../../ssh-keys/yubi.pub;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    ssh = {
      enable = true;
      identityPath = "/run/dev-secret/ssh/id_ed25519_yubi";
      addKeysToAgent = false;
    };
    yazi.enable = true;
    zsh = {
      enable = true;
      tokenDir = "/run/tokens/dev";
    };
    box = {
      enable = true;
      user = username;
      homeManagerPackage = inputs.self.homeConfigurations."sandbox-dev".activationPackage;
      yubiHandle = "/run/dev-secret/ssh/id_ed25519_yubi";
      tokenDir = "/run/tokens/dev";
    };
  };

  home = {
    username = username;
    homeDirectory = homeDir;
    stateVersion = "25.11";
  };

  xdg.userDirs = {
    enable = true;
    createDirectories = false;
    setSessionVariables = true;
    projects = "${homeDir}/.projects";
    publicShare = "${homeDir}/.public";
    templates = "${homeDir}/.templates";
  };

  systemd.user.startServices = false;
  programs = {
    home-manager.enable = true;
    bash = {
      enable = true;
      initExtra = "exec ${lib.getExe pkgs.zsh}";
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      silent = true;
    };
    # No Wayland socket. Clipboard only reachable via foot's OSC-52.
    zsh.shellAliases.wl-copy = "osc-copy";
  };

  home.packages = with pkgs; [
    curl
    oscclip
  ];
}

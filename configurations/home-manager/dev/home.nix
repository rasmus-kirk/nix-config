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
    scripts.enable = true;
    jiten.enable = true;

    claude.enable = true;

    git = {
      enable = true;
      signKey = "${homeDir}/.ssh/id_ed25519_yubi.pub";
      signPubKey = ../../../pubkeys/yubi.pub;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };

    ssh = {
      enable = true;
      identityPath = "${homeDir}/.ssh/id_ed25519_yubi";
      # No agent: `sudo -i` has no logind session, so every use touches the key.
      addKeysToAgent = false;
    };

    yazi.enable = true;

    zsh.enable = true;

    box = {
      enable = true;

      # The box keeps dev's identity: home mounted at /home/dev inside, and a
      # sandbox config that declares dev, so the $USER/$HOME home-manager
      # checks pass on inherited values rather than rewritten ones.
      user = username;

      homeManagerPackage = inputs.self.homeConfigurations."sandbox-dev".activationPackage;
    };
  };

  home.username = username;
  home.homeDirectory = homeDir;
  home.stateVersion = "25.11";

  xdg.userDirs = {
    enable = true;
    createDirectories = false;
    setSessionVariables = true;
    projects = "${homeDir}/.projects";
    publicShare = "${homeDir}/.public";
    templates = "${homeDir}/.templates";
  };

  systemd.user.startServices = false;

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      exec ${lib.getExe pkgs.zsh}
    '';
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
  };

  # dev has no Wayland socket; the clipboard is reachable only via foot's OSC-52.
  programs.zsh.shellAliases.wl-copy = "osc-copy";

  home.packages = with pkgs; [
    claude-code
    curl
    oscclip
  ];
}

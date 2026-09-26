{
  pkgs,
  lib,
  config,
  boxUser,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  # Set by the flake's mkSandbox, from kirk.box.user on the host side.
  username = boxUser;
  machine = "sandbox";
in {
  kirk = {
    terminalTools.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      # The box has no private key or YubiKey, so it cannot sign.
      # signKey is the store copy, which every box can resolve.
      signKey = toString ../../../pubkeys/yubi.pub;
      signPubKey = ../../../pubkeys/yubi.pub;
      signByDefault = false;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    homeManagerScripts = {
      enable = true;
      extraNixOptions = true;
      configDir = configDir;
      machine = machine;
    };
    jiten.enable = false;
    scripts.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh = {
      enable = true;
      # No identityPath, because the box has no SSH key access.
    };
    userDirs = {
      enable = true;
      rootDir = dataDir;
      autoSortDownloads = true;
    };
    zsh = {
      enable = true;
      # Default stateDir keeps history in $HOME/.zsh_history, inside the box's writable home.
    };
  };

  systemd.user.startServices = false;

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      exec ${lib.getExe pkgs.zsh}
    '';
  };

  programs.zsh.profileExtra = ''
    # Yazi
    export TERM=foot
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
    # The box is the jail, so trust every .envrc inside it. Never record that
    # trust on the host, where the .envrc would then run unsandboxed.
    config.whitelist.prefix = ["/"];
  };

  home.packages = with pkgs; [
    # The box PATH contains only this profile, so it needs a base userland.
    # nix-direnv needs `nix` to build a project's devshell.
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    less
    nix

    claude-code
    curl

    wl-clipboard
  ];
}

# My home manager config
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
      # signByDefault=false: the box has no private key or YubiKey, so it
      # cannot sign. signKey is the store copy, resolvable inside every box.
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
      # No identityPath — box has no SSH key access.
    };
    userDirs = {
      enable = true;
      rootDir = dataDir;
      autoSortDownloads = true;
    };
    zsh = {
      enable = true;
      # Don't override stateDir — history goes to $HOME/.zsh_history,
      # which lives inside the box's writable state-dir home.
    };
  };

  systemd.user.startServices = false;

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      # if [[ "$PWD" == "$HOME" ]]; then
      #   cd /data
      # fi

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
    # Trust every .envrc, but only in here. The box is the jail, so running a
    # project's .envrc inside it is the point; what must not happen is the
    # launcher marking it trusted on the *host*, which would let it execute
    # outside the sandbox the next time that directory is entered.
    config.whitelist.prefix = ["/"];
  };

  home.packages = with pkgs; [
    # Base userland. The box's PATH is only this profile, so if it isn't here
    # it doesn't exist in the box — including `ls`. `nix` is needed by
    # nix-direnv to build a project's devshell.
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    less
    nix

    # Misc
    claude-code
    curl

    # Misc Terminal Tools
    wl-clipboard
  ];
}

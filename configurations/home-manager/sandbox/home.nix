# My home manager config
{
  pkgs,
  lib,
  config,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  username = "user";
  machine = "sandbox";
in {
  kirk = {
    terminalTools.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      signKey = "${secretDir}/ssh/id_ed25519_yubi.pub";
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
      identityPath = "${secretDir}/ssh/id_ed25519_yubi";
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
  };

  home.packages = with pkgs; [
    # Misc
    claude-code
    curl

    # Misc Terminal Tools
    wl-clipboard
  ];

  # Box has no direct egress except tinyproxy. To make `git push` (over SSH)
  # work, route github.com through GitHub's HTTPS-port SSH listener
  # (ssh.github.com:443) and tunnel it through tinyproxy via socat+CONNECT.
  # Transparent: stock `git@github.com:owner/repo` URLs just work.
  programs.ssh.matchBlocks."github.com" = {
    hostname = "ssh.github.com";
    port = 443;
    user = "git";
    extraOptions = {
      ProxyCommand = "${pkgs.socat}/bin/socat - PROXY:10.0.2.2:%h:%p,proxyport=8888";
    };
  };
}

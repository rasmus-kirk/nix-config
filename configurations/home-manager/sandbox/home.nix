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
    box.brokerClient.enable = true;
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

  # OpenSSH refuses configs not owned by the current user or root. Inside the
  # box's user-namespace, host root (which owns everything in /nix/store) maps
  # to "nobody" — so home-manager's standard symlink ~/.ssh/config →
  # /nix/store/.../config fails SSH's strict ownership check.
  #
  # Fix: materialize the config as a real, user-owned file. linkGeneration
  # creates the symlink as usual; the entryBefore hook clears any stale
  # materialized file so the next switch can re-link cleanly; the entryAfter
  # hook copies the freshly-linked target's content into a real file.
  home.activation.materializeSshConfigPre = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    if [ -e "$HOME/.ssh/config" ] && [ ! -L "$HOME/.ssh/config" ]; then
      $DRY_RUN_CMD rm -f "$HOME/.ssh/config"
    fi
  '';
  home.activation.materializeSshConfigPost = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    link="$HOME/.ssh/config"
    if [ -L "$link" ]; then
      target=$(readlink -f "$link" 2>/dev/null || true)
      if [ -n "$target" ] && [ -f "$target" ]; then
        $DRY_RUN_CMD rm -f "$link"
        $DRY_RUN_CMD cp --no-preserve=mode,ownership "$target" "$link"
        $DRY_RUN_CMD chmod 0600 "$link"
      fi
    fi
  '';
}

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
      # No signKey — box has no YubiKey access. Commits land unsigned;
      # use git-batch-sign on the host to amend-sign a range when ready.
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
      # No identityPath — box has no SSH key access. Git push/pull/fetch
      # flow through the host approval TUI which uses the host's YubiKey.
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

  # Box no longer talks to GitHub directly — git push/pull/fetch all
  # route through the host approval TUI, which performs the SSH op
  # from the host (where the YubiKey lives). Commits in box are
  # unsigned by design (commit.gpgsign = false below); use
  # `git-batch-sign` to amend-sign a range on the host when ready.
  programs.git.settings.commit.gpgsign = false;
}

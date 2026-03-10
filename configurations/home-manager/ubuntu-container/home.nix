# My home manager config
{
  pkgs,
  config,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  username = "ubuntu";
  machine = "ubuntu-container";
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
    jiten.enable = true;
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
      stateDir = stateDir;
    };
  };

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

      # exec zsh
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

    # Misc Terminal Tools
    wl-clipboard
  ];
}

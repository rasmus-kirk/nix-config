# My home manager config
{pkgs, ...}: let
  username = "deck";
  machine = "deck";
  dataDir = "/data";
  configDir = "/home/deck/.system-configuration";
  secretDir = "/home/deck/.secret";
in {
  kirk = {
    terminalTools.enable = true;
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    homeManagerScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
    ssh = {
      enable = true;
      identityPath = "${secretDir}/deck/ssh/id_ed25519";
    };
    userDirs = {
      enable = true;
      autoSortDownloads = true;
    };
    yazi.enable = true;
    zathura.enable = true;
    zsh.enable = true;
    fonts.enable = true;
    rustle.enable = true;
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  nix = {
    package = pkgs.nix;
    settings.experimental-features = ["nix-command" "flakes"];
  };

  # Enable ZSH through a hack
  programs.bash = {
    enable = true;
    initExtra = "exec zsh";
  };

  home.packages = with pkgs; [
    # Misc
    mpv
    qbittorrent
    keepassxc

    # Chat
    signal-desktop

    # Misc Terminal Tools
    wl-clipboard
  ];
}

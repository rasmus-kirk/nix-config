{pkgs, ...}: let
  secretDir = "/data/.secret";
  configDir = "/data/.system-configuration";
  machine = "pi";
  username = "user";
in {
  kirk = {
    terminalTools.enable = true;
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix = {
      enable = true;
      installMostLsps = false;
      extraPackages = with pkgs; [nil marksman nodePackages_latest.bash-language-server];
    };
    homeManagerScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
    userDirs = {
      enable = true;
      autoSortDownloads = false;
    };
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh = {
      enable = true;
      identityPath = "${secretDir}/${machine}/ssh/id_ed25519";
    };
    zsh.enable = true;
    fonts.enable = true;
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

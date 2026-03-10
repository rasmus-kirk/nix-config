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
    # foot.enable = true;
    # mpv.enable = true;
    # mvi.enable = true;
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
    # zathura = {
    #   enable = true;
    #   darkmode = false;
    # };
    zsh = {
      enable = true;
      stateDir = stateDir;
    };
    # fonts.enable = true;
    # chromiumLaunchers = {
    #   enable = true;
    #   stateDir = stateDir;
    #   launchers = {
    #     gemini = "https://gemini.google.com/";
    #     claude-website = "https://claude.ai/";
    #     slack = "https://concordium.slack.com/";
    #   };
    # };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  # services = {
  #   podman.enable = true;
  #   syncthing.enable = true;
  # };

  # systemd.user.tmpfiles.rules = [
  #   "d  ${stateDir}/thunderbird     0755 user user - -"
  #   "d  ${stateDir}/cosmic          0755 user user - -"
  #   "d  ${stateDir}/cosmic/config   0755 user user - -"
  #   "d  ${stateDir}/cosmic/comp     0755 user user - -"
  #   "d  ${stateDir}/cosmic/local    0755 user user - -"
  #   "d  ${stateDir}/firefox         0755 user user - -"
  #   "d  ${stateDir}/firefox/config  0755 user user - -"
  #   "d  ${stateDir}/firefox/home    0755 user user - -"
  #   "d  ${stateDir}/chromium        0755 user user - -"
  #   "d  ${stateDir}/syncthing       0755 user user - -"
  #   "d  ${stateDir}/syncthing/state 0755 user user - -"
  #   "d  ${stateDir}/syncthing/sync  0755 user user - -"

  #   "L+ ${config.home.homeDirectory}/.thunderbird                  - - - - ${stateDir}/thunderbird"
  #   "L+ ${config.home.homeDirectory}/.mozilla                      - - - - ${stateDir}/firefox/home"
  #   "L+ ${config.home.homeDirectory}/.config/mozilla               - - - - ${stateDir}/firefox/config"
  #   "L+ ${config.home.homeDirectory}/.config/chromium              - - - - ${stateDir}/chromium"
  #   "L+ ${config.home.homeDirectory}/.local/state/syncthing        - - - - ${stateDir}/syncthing/state"

  #   "L+ ${config.home.homeDirectory}/.config/cosmic             - - - - ${stateDir}/cosmic/config"
  #   "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
  #   "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"
  # ];

  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ "$PWD" == "$HOME" ]]; then
        cd /data
      fi

      exec zsh
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

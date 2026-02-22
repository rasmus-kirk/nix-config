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
  username = "user";
  machine = "deck-oled";
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    homeManagerScripts = {
      enable = false;
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
      identityPath = "${secretDir}/ssh/id_ed25519";
    };
    userDirs = {
      enable = true;
      rootDir = dataDir;
      autoSortDownloads = true;
    };
    zathura = {
      enable = true;
      darkmode = false;
    };
    zsh = {
      enable = true;
      stateDir = stateDir;
    };
    fonts.enable = true;
    chromiumLaunchers = {
      enable = true;
      stateDir = stateDir;
      launchers = {
        t3 = "https://t3.chat/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  # programs.home-manager.enable = true;

  systemd.user.tmpfiles.rules = [
    "d  ${stateDir}/thunderbird     0755 user users - -"
    "d  ${stateDir}/cosmic          0755 user users - -"
    "d  ${stateDir}/cosmic/config   0755 user users - -"
    "d  ${stateDir}/cosmic/comp     0755 user users - -"
    "d  ${stateDir}/cosmic/local    0755 user users - -"
    "d  ${stateDir}/firefox         0755 user users - -"
    "d  ${stateDir}/firefox/config  0755 user users - -"
    "d  ${stateDir}/firefox/home    0755 user users - -"
    "d  ${stateDir}/chromium        0755 user users - -"
    "d  ${stateDir}/syncthing       0755 user users - -"
    "d  ${stateDir}/syncthing/state 0755 user users - -"
    "d  ${stateDir}/syncthing/sync  0755 user users - -"

    "L+ ${config.home.homeDirectory}/.thunderbird               - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.local/state/syncthing     - - - - ${stateDir}/syncthing/state"

    "L+ ${config.home.homeDirectory}/.config/cosmic             - - - - ${stateDir}/cosmic/config"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"
  ];

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
    keepassxc
    thunderbird
    feishin

    # Browsers
    librewolf
    chromium

    # Chat
    signal-desktop-bin

    # Misc Terminal Tools
    wl-clipboard
    yt-dlp
  ];
}

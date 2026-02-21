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
    monero.enable = true;
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
      identityPath = "${secretDir}/id_ed25519";
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
    syncthing = {
      enable = true;
      dataDir = "${stateDir}/syncthing";
    };
    chromiumLaunchers = {
      enable = true;
      stateDir = stateDir;
      launchers = {
        t3 = "https://t3.chat/";
        mattermost = "https://mattermost.cs.au.dk/";
        slack = "https://concordium.slack.com/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  services.podman.enable = true;

  systemd.user.tmpfiles.rules = [
    "d  ${stateDir}/thunderbird                   0755 user users - -"
    "L+ ${config.home.homeDirectory}/.thunderbird -    -    -    - ${stateDir}/thunderbird"
  ];

  programs.bash = {
    enable = true;
    # profileExtra = ''
    #   # Fix programs not showing up
    #   export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

    #   export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
    # '';

    initExtra = "exec zsh";
  };

  programs.zsh.profileExtra = ''
    # export PATH=$PATH:~/.cargo/bin:~/.local/bin

    # Yazi
    export TERM=foot

    # export XCURSOR_THEME="Capitaine Cursors (Gruvbox)"
    # export XCURSOR_PATH="$XCURSOR_PATH":/usr/share/icons:~/.local/share/icons
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

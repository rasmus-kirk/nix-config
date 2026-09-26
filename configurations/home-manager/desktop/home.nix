{
  pkgs,
  config,
  inputs,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state/user";
  username = "user";
  machine = "desktop";
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    # This box is always on, so the TV follows input and audio activity, not host power.
    # While the TV is awake, a sub-audible pulse keeps the speaker out of EU-mandated standby.
    cec = {
      enable = true;
      sink = "alsa_output.pci-0000_03_00.1.hdmi-stereo"; # the LG TV (Navi 48 HDMI; node.nick "LG TV")
      keepAwake.debug = true; # TEMP: verify monitor RMS in the journal
      # Controller volume keys only reach the system volume, so relay it to the AVR over CEC.
      controllerVolume.enable = true;
    };
    xdgMime.enable = true;
    stateBackup.enable = false;
    git = {
      enable = true;
      signKey = "${secretDir}/ssh/id_ed25519_yubi.pub";
      signPubKey = ../../../pubkeys/yubi.pub;
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
    jiten = {
      enable = true;
      stateDir = stateDir;
    };
    scripts.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh = {
      enable = true;
      addKeysToAgent = true;
      identityPath = "${secretDir}/ssh/id_ed25519_yubi";
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
    box.enable = true;
    chromiumLaunchers = {
      enable = true;
      stateDir = stateDir;
      launchers = {
        youtube = "https://youtube.com/";
        discord = "https://discord.com/channels/@me";
        proton = "https://mail.proton.me/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  systemd.user.tmpfiles.rules = [
    "L+ ${config.home.homeDirectory}/.thunderbird               - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.ssh/known_hosts          - - - - ${stateDir}/ssh/known_hosts"
    "L+ ${config.home.homeDirectory}/.config/btop/btop.conf     - - - - ${stateDir}/btop/btop.conf"

    "L+ ${config.home.homeDirectory}/.config/cosmic             - - - - ${stateDir}/cosmic/config"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"

    "L+ ${config.home.homeDirectory}/.claude                    - - - - ${stateDir}/claude/state"
    "L+ ${config.home.homeDirectory}/.claude.json               - - - - ${stateDir}/claude/claude.json"

    "L+ ${config.home.homeDirectory}/.local/share/Steam         - - - - ${stateDir}/steam/steam"
    "L+ ${config.home.homeDirectory}/.steam                     - - - - ${stateDir}/steam/steam-compat"
    # Gamescope and steamos-manager settings live outside the Steam root, so the
    # @root rollback resets them each boot unless they are persisted here.
    "L+ ${config.home.homeDirectory}/.config/gamescope          - - - - ${stateDir}/steam/gamescope"
    "L+ ${config.home.homeDirectory}/.config/steamos-manager    - - - - ${stateDir}/steam/steamos-manager"

    # Jellyfin Media Player (Qt5, nixpkgs-2405) and Plezy state, persisted across the @root rollback.
    "L+ ${config.home.homeDirectory}/.local/share/jellyfinmediaplayer - - - - ${stateDir}/jellyfinmediaplayer"
    "L+ ${config.home.homeDirectory}/.local/share/com.edde746.plezy - - - - ${stateDir}/plezy"
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
    # GitHub PAT for the github MCP plugin when Claude Code runs on host.
    # In the box, this token is exported via the sandbox initScript; this
    # mirrors that behaviour for host shells.
    if [ -r ${secretDir}/github/qms-pat-global-ro ]; then
      export GITHUB_PERSONAL_ACCESS_TOKEN="$(tr -d '[:space:]' < ${secretDir}/github/qms-pat-global-ro)"
    fi
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
  };

  # Relaunches Steam inside the running gamescope session and re-runs the steam-shortcuts sync first.
  home.shellAliases.restart-steam = "systemctl --user restart steam-launcher.service";

  # With autologin KWallet can never auto-unlock, and Chromium blocks on its prompt.
  # Disabled, apps fall back to their own secret stores.
  xdg.configFile."kwalletrc".text = ''
    [Wallet]
    Enabled=false
    First Use=false
  '';

  home.packages = with pkgs; [
    bubblewrap
  ];
}

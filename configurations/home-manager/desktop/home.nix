# My home manager config
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
    # TV liveness over HDMI-CEC, subsuming rustle (no standalone kirk.rustle
    # here anymore). Always-on box, so the TV follows *activity*, not power:
    # idle (no /dev/input events AND no real audio) for idleMinutes -> TV
    # standby; any key/controller/mouse or audio -> wake. While the TV is
    # awake it emulates rustle: watches the sink monitor (RMS) and, after
    # ~10 min of silence, plays a 10s sub-audible pulse so the speaker doesn't
    # hit its EU-mandated standby — reset on real sound, nothing while asleep.
    cec = {
      enable = true;
      sink = "alsa_output.pci-0000_03_00.1.hdmi-stereo"; # the LG TV (Navi 48 HDMI; node.nick "LG TV")
      keepAwake.debug = true; # TEMP: verify monitor RMS in the journal
      # Relay controller/system volume on the TV sink to the AVR over CEC (the
      # controller's volume keys only reach the system volume, not our evdev).
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

  # All home-manager user state lives under ${stateDir} (= /data/.state/user),
  # a single user-owned subtree created at system level (configuration.nix).
  #
  # syncthing user-level entries removed: this box runs system-level
  # services.syncthing (configDir = /data/.state/syncthing) owned by
  # the syncthing system user — a user-level syncthing would conflict.
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
    # jovian/gamescope gaming-mode settings live OUTSIDE the Steam root, so
    # they need explicit persistence or the @root rollback resets them every
    # boot: gamescope display modes/EDID + steamos-manager state.
    "L+ ${config.home.homeDirectory}/.config/gamescope          - - - - ${stateDir}/steam/gamescope"
    "L+ ${config.home.homeDirectory}/.config/steamos-manager    - - - - ${stateDir}/steam/steamos-manager"

    # Jellyfin client state, persisted across the @root rollback. The native
    # jellyfin-desktop client was removed (can't run under gamescope); the web UI
    # runs in a Chromium kiosk whose profile lives under ${stateDir}/jellyfin-web.
    #   - Plezy (Flutter, nixpkgs): ~/.local/share/com.edde746.plezy.
    # Old Qt5 JMP (jellyfin-media-player from nixpkgs-2405) — its login/config.
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

  # Restart Steam in game mode: bounces Jovian's steam-launcher user unit, which
  # re-runs the steam-shortcuts sync first (so tile/shortcut changes apply) and
  # relaunches the Steam client inside the existing gamescope session — no reboot
  # or full session restart. (For a stuck gamescope/display itself, the physical
  # power button now triggers `systemctl soft-reboot` — see acpid in the desktop
  # configuration.nix; or run it over SSH.)
  home.shellAliases.restart-steam = "systemctl --user restart steam-launcher.service";

  # Kill KWallet. With autologin it can never auto-unlock, so it just nags on
  # every launch — and Chromium blocks on that prompt (its KDE "safe storage"
  # backend), which is why only Chromium, only on Plasma, "couldn't connect".
  # Disabling the subsystem makes apps fall back to their own stores.
  xdg.configFile."kwalletrc".text = ''
    [Wallet]
    Enabled=false
    First Use=false
  '';

  home.packages = with pkgs; [
    bubblewrap
  ];
}

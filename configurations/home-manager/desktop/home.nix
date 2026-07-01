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
      sink = "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra2"; # the LG TV (Navi 48 HDMI)
      keepAwake.debug = true; # TEMP: verify monitor RMS in the journal
    };
    xdgMime.enable = true;
    stateBackup.enable = false;
    git = {
      enable = true;
      signKey = "${secretDir}/ssh/id_ed25519_yubi.pub";
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
    box = {
      enable = true;
      githubTokenFile = "${secretDir}/github/qms-pat-global-ro";
      githubPrBroker = {
        enable = true;
        writeTokenFile = "${secretDir}/github/qms-pat-pr-rw";
      };
    };
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
  # Because that parent is writable by 'user', we create the per-app subdirs
  # here via user-tmpfiles, then point the home dotfiles at them with L+.
  #
  # cosmic IS symlinked here too. The earlier EEXIST panic at
  # cosmic-comp config/mod.rs:172 was NOT caused by the symlink itself but
  # by a DANGLING one: the old "d" rules ran as user-tmpfiles against the
  # then root-owned /data/.state, failed with EACCES, so the targets never
  # existed and ~/.config/cosmic pointed at nothing. Now that the parent is
  # user-owned the "d" rules create the targets first, so the links resolve.
  #
  # syncthing user-level entries removed: this box runs system-level
  # services.syncthing (configDir = /data/.state/syncthing) owned by
  # the syncthing system user — a user-level syncthing would conflict.
  systemd.user.tmpfiles.rules = [
    "d ${stateDir}/thunderbird     0755 user users - -"
    "d ${stateDir}/firefox         0755 user users - -"
    "d ${stateDir}/firefox/config  0755 user users - -"
    "d ${stateDir}/firefox/home    0755 user users - -"
    "d ${stateDir}/chromium        0755 user users - -"
    # Dedicated Chromium profiles for the game-mode Steam tiles, each its own
    # Steam-tracked primary instance (so --force-device-scale-factor applies) and
    # its own logins/YouTube account: the Jellyfin kiosk, plus a per-person
    # browser tile for Rasmus and his girlfriend (see kirk.steamShortcuts).
    "d ${stateDir}/jellyfin-web    0700 user users - -"
    "d ${stateDir}/chromium-rasmus 0700 user users - -"
    "d ${stateDir}/chromium-naja   0700 user users - -"
    "d ${stateDir}/yubico          0755 user users - -"
    "d ${stateDir}/claude          0755 user users - -"
    "d ${stateDir}/claude/state    0755 user users - -"
    "d ${stateDir}/steam                 0755 user users - -"
    "d ${stateDir}/steam/steam           0755 user users - -"
    "d ${stateDir}/steam/steam-compat    0755 user users - -"
    "d ${stateDir}/steam/gamescope       0755 user users - -"
    "d ${stateDir}/steam/steamos-manager 0755 user users - -"
    "d ${stateDir}/plezy           0755 user users - -"
    "d ${stateDir}/jellyfinmediaplayer     0755 user users - -"
    "d ${stateDir}/zsh             0755 user users - -"
    "d ${stateDir}/cosmic          0755 user users - -"
    "d ${stateDir}/cosmic/config   0755 user users - -"
    "d ${stateDir}/cosmic/comp     0755 user users - -"
    "d ${stateDir}/cosmic/local    0755 user users - -"
    "d ${stateDir}/btop            0755 user users - -"

    "L+ ${config.home.homeDirectory}/.thunderbird               - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.config/Yubico             - - - - ${stateDir}/yubico"
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

  # Kill KWallet. With autologin it can never auto-unlock, so it just nags on
  # every launch — and Chromium blocks on that prompt (its KDE "safe storage"
  # backend), which is why only Chromium, only on Plasma, "couldn't connect".
  # Disabling the subsystem makes apps fall back to their own stores.
  xdg.configFile."kwalletrc".text = ''
    [Wallet]
    Enabled=false
    First Use=false
  '';

  # box-approver is launched manually by the user from a terminal. We wrap
  # it in a small shell script that hard-codes all the BOX_* env vars (PAT
  # paths, notify binaries, sound file) so launches survive stale shells /
  # non-shell launchers — no reliance on home.sessionVariables. Mirrors the
  # work machine; uses the same QMS PAT/Linear secrets.
  home.packages = let
    boxBrokerPkg = inputs.self.packages.${pkgs.system}.box-broker;
    boxApproverWrapped = pkgs.writeShellApplication {
      name = "box-approver";
      runtimeInputs = [];
      inheritPath = true;
      text = ''
        export BOX_GH_PAT_FILE="${secretDir}/github/qms-pat-pr-rw"
        export BOX_LINEAR_PAT_FILE="${secretDir}/linear/pat"
        export BOX_NOTIFY_BIN="${pkgs.libnotify}/bin/notify-send"
        export BOX_PW_CAT_BIN="${pkgs.pipewire}/bin/pw-cat"
        export BOX_NOTIFY_SOUND="${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message.oga"
        exec ${boxBrokerPkg}/bin/box-approver "$@"
      '';
    };
  in
    with pkgs; [
      bubblewrap
      socat
      boxApproverWrapped
    ];
}

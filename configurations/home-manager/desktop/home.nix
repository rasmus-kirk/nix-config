# My home manager config
{
  pkgs,
  config,
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
    # Keep the LG TV's HDMI audio sink from powering down on silence by
    # playing a sub-audible 20Hz tone after idle. Defaults; auto-suspend
    # stays off (minutesUntilSuspend = 0) since this box is also a server.
    rustle.enable = true;
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
    jiten.enable = true;
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
    "d ${stateDir}/yubico          0755 user users - -"
    "d ${stateDir}/claude          0755 user users - -"
    "d ${stateDir}/claude/state    0755 user users - -"
    "d ${stateDir}/steam           0755 user users - -"
    "d ${stateDir}/steam-compat    0755 user users - -"
    "d ${stateDir}/zsh             0755 user users - -"
    "d ${stateDir}/cosmic          0755 user users - -"
    "d ${stateDir}/cosmic/config   0755 user users - -"
    "d ${stateDir}/cosmic/comp     0755 user users - -"
    "d ${stateDir}/cosmic/local    0755 user users - -"

    "L+ ${config.home.homeDirectory}/.thunderbird               - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.config/Yubico             - - - - ${stateDir}/yubico"

    "L+ ${config.home.homeDirectory}/.config/cosmic             - - - - ${stateDir}/cosmic/config"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"

    "L+ ${config.home.homeDirectory}/.claude                    - - - - ${stateDir}/claude/state"
    "L+ ${config.home.homeDirectory}/.claude.json               - - - - ${stateDir}/claude/claude.json"

    "L+ ${config.home.homeDirectory}/.local/share/Steam         - - - - ${stateDir}/steam"
    "L+ ${config.home.homeDirectory}/.steam                     - - - - ${stateDir}/steam-compat"
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

  home.packages = with pkgs; [];
}

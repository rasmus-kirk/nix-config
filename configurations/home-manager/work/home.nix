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
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      signKey = "${secretDir}/ssh/id_ed25519_yubi.pub";
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
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
    sandbox = {
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
        Github = "https://github.com/";
        Calendar = "https://calendar.google.com/";
        "Family Link" = "https://familylink.google.com/";
        "Claude Chat" = "https://claude.ai/new";
        Linear = "https://linear.app/qms-finance/team/QMS";
        Meet = "https://meet.google.com/";
        Gmail = "https://mail.google.com/";
        Slack = "https://app.slack.com/client/T0AGG8JCJNS/C0AGBU9AFNF";
        Deel = "https://app.deel.com";
        "Proton Mail" = "https://mail.proton.me/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

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
    "d  ${stateDir}/yubico          0755 user users - -"
    "d  ${stateDir}/syncthing       0755 user users - -"
    "d  ${stateDir}/syncthing/state 0755 user users - -"
    "d  ${stateDir}/syncthing/sync  0755 user users - -"
    "d  ${stateDir}/claude          0755 user users - -"
    "d  ${stateDir}/claude/state    0755 user users - -"

    "L+ ${config.home.homeDirectory}/.thunderbird               - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.local/state/syncthing     - - - - ${stateDir}/syncthing/state"
    "L+ ${config.home.homeDirectory}/.config/Yubico             - - - - ${stateDir}/yubico"

    "L+ ${config.home.homeDirectory}/.config/cosmic             - - - - ${stateDir}/cosmic/config"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"

    "L+ ${config.home.homeDirectory}/.claude                    - - - - ${stateDir}/claude/state"
    "L+ ${config.home.homeDirectory}/.claude.json               - - - - ${stateDir}/claude/claude.json"
  ];

  # services.syncthing.enable = true;

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
    # In the box, ~/.secret/github/pat is exported via the sandbox initScript;
    # this mirrors that behaviour for host shells.
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

  home.packages = with pkgs; [ claude-code bubblewrap socat finamp ];

  # Watch /tmp/box-notify and dispatch any file dropped there as a desktop
  # notification. Lets processes inside the `box` sandbox notify the host
  # without giving them DBUS access.
  systemd.user.paths.box-notify = {
    Unit.Description = "Watch /tmp/box-notify for notification drops";
    Path = {
      PathExistsGlob = "/tmp/box-notify/[!.]*";
      MakeDirectory = true;
      DirectoryMode = "0755";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.services.box-notify = {
    Unit.Description = "Dispatch /tmp/box-notify drops via notify-send";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "box-notify-dispatch" ''
        set -u
        for f in /tmp/box-notify/[!.]*; do
          [ -f "$f" ] || continue
          TITLE=$(${pkgs.coreutils}/bin/head -n1 "$f")
          BODY=$(${pkgs.coreutils}/bin/tail -n+2 "$f")
          # Play attention sound in parallel with the popup. Backgrounded so
          # the popup fires immediately; `wait` keeps the systemd oneshot
          # alive until pw-cat finishes, otherwise KillMode=control-group
          # reaps the sound mid-playback.
          ${pkgs.pipewire}/bin/pw-cat --playback ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message.oga >/dev/null 2>&1 &
          ${pkgs.libnotify}/bin/notify-send -- "$TITLE" "$BODY" || true
          wait
          ${pkgs.coreutils}/bin/rm -f "$f"
        done
      ''}";
    };
  };
}

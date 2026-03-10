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
  machine = "work";
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
        gemini = "https://gemini.google.com/";
        claude-website = "https://claude.ai/";
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

  services = {
    podman.enable = true;
    syncthing.enable = true;
  };

  systemd.user.tmpfiles.rules = [
    "d  ${stateDir}/thunderbird     0755 user user - -"
    "d  ${stateDir}/cosmic          0755 user user - -"
    "d  ${stateDir}/cosmic/config   0755 user user - -"
    "d  ${stateDir}/cosmic/comp     0755 user user - -"
    "d  ${stateDir}/cosmic/local    0755 user user - -"
    "d  ${stateDir}/firefox         0755 user user - -"
    "d  ${stateDir}/firefox/config  0755 user user - -"
    "d  ${stateDir}/firefox/home    0755 user user - -"
    "d  ${stateDir}/chromium        0755 user user - -"
    "d  ${stateDir}/syncthing       0755 user user - -"
    "d  ${stateDir}/syncthing/state 0755 user user - -"
    "d  ${stateDir}/syncthing/sync  0755 user user - -"

    "L+ ${config.home.homeDirectory}/.thunderbird                  - - - - ${stateDir}/thunderbird"
    "L+ ${config.home.homeDirectory}/.mozilla                      - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla               - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium              - - - - ${stateDir}/chromium"
    "L+ ${config.home.homeDirectory}/.local/state/syncthing        - - - - ${stateDir}/syncthing/state"

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
    keepassxc
    thunderbird
    feishin
    claude-code

    # Browsers
    firefox
    chromium

    # Chat
    signal-desktop

    # Misc Terminal Tools
    wl-clipboard
    yt-dlp

    (pkgs.writeShellApplication {
      name = "pm";
      inheritPath = true;
      runtimeInputs = [
        age
        age-plugin-fido2-hmac
        csvkit
        nano
        wl-clipboard
        coreutils
      ];
      text = ''
        # Configuration
        SECRET_FILE="${secretDir}/passwords/passwords.age"
        TEMP_DIR="/dev/shm/pm-$(id -u)"
        TEMP_FILE="$TEMP_DIR/decrypted.csv"
        PUB_KEY=$(tr -d '\n' < "${secretDir}/passwords/key.pub")
        TIMEOUT=10

        mkdir -p "$(dirname "$SECRET_FILE")" # Ensure directory for secret exists
        mkdir -p "$TEMP_DIR" && chmod 700 "$TEMP_DIR" # Secure RAM directory setup

        cleanup() {
          if [ -f "$TEMP_FILE" ]; then
            shred -u "$TEMP_FILE" 2>/dev/null
          fi
          rmdir "$TEMP_DIR" 2>/dev/null
        }
        trap cleanup EXIT

        case "$1" in
            edit)
              if [ -f "$SECRET_FILE" ]; then
                age --decrypt -j fido2-hmac -o "$TEMP_FILE" "$SECRET_FILE" || exit 1
              else
                echo "name,user,pass" > "$TEMP_FILE"
              fi
              ''${EDITOR:-nano} "$TEMP_FILE"

              age -r "$PUB_KEY" -o "$SECRET_FILE" "$TEMP_FILE"
              echo "Changes encrypted to $SECRET_FILE."
              ;;

            pass)
              SEARCH_TERM="''${2:-}"
              if [ -z "$SEARCH_TERM" ]; then
                echo "Usage: pm pass <name>"
                exit 1
              fi

              if [ ! -f "$SECRET_FILE" ]; then
                echo "Error: $SECRET_FILE does not exist."
                exit 1
              fi

              age --decrypt -j fido2-hmac -o "$TEMP_FILE" "$SECRET_FILE" || exit 1
              csvgrep -c name -m "$SEARCH_TERM" "$TEMP_FILE" |
                csvcut -c pass |
                tail -n 1 |
                tr -d '\n' |
                wl-copy --paste-once

              echo "Password for '$SEARCH_TERM' copied."
      
              ( sleep "$TIMEOUT" && wl-copy --clear ) &
              ;;

            user)
              SEARCH_TERM="''${2:-}"
              if [ -z "$SEARCH_TERM" ]; then
                echo "Usage: pm user <name>"
                exit 1
              fi

              if [ ! -f "$SECRET_FILE" ]; then
                echo "Error: $SECRET_FILE does not exist."
                exit 1
              fi

              age --decrypt -j fido2-hmac -o "$TEMP_FILE" "$SECRET_FILE" || exit 1
              csvgrep -c name -m "$SEARCH_TERM" "$TEMP_FILE" |
                csvcut -c user |
                tail -n 1 |
                tr -d '\n' |
                wl-copy --paste-once

              echo "Username/Email for '$SEARCH_TERM' copied."
      
              ( sleep "$TIMEOUT" && wl-copy --clear ) &
              ;;

            *)
              echo "Usage: pm {edit|user <name>|pass <name>}"
              exit 1
              ;;
        esac
      '';
    })
  ];
}

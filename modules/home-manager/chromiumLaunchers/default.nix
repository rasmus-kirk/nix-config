{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.chromiumLaunchers;
  stateRoot = if cfg.stateDir == null 
    then "${config.home.homeDirectory}/.local/state/chromium-launchers"
    else "${cfg.stateDir}/chromium-launchers";
  iconStorage = "${stateRoot}/icons";
  fetcherScript = pkgs.writeShellApplication {
    name = "fetch-webapp-icons";
    runtimeInputs = with pkgs; [ wget imagemagick coreutils ];
    inheritPath = false;
    text = ''
      set +e
      mkdir -p "${iconStorage}"
      ${concatStringsSep "\n" (mapAttrsToList (name: url:
        let
          domain = lib.elemAt (lib.splitString "/" (lib.last (lib.splitString "://" url))) 0;
        in ''
          if [ ! -f "${iconStorage}/${name}.png" ]; then
            wget -qO "${iconStorage}/${name}.ico" "https://icons.duckduckgo.com/ip3/${domain}.ico"
            if [ -s "${iconStorage}/${name}.ico" ]; then
              tmpdir=$(mktemp -d)
              magick "${iconStorage}/${name}.ico" "$tmpdir/frame.png"

              # echo "Workdir: $tmpdir"
              # ls "$tmpdir"

              largest=""
              largest_size=0
              for f in "$tmpdir"/frame*.png; do
                if [ -f "$f" ]; then
                  size=$(wc -c < "$f")
                  if [ "$size" -gt "$largest_size" ]; then
                    largest_size="$size"
                    largest="$f"
                  fi
                fi
              done
              if [ -n "$largest" ]; then
                mv "$largest" "${iconStorage}/${name}.png"
              else
                echo "Warning: failed to convert favicon for ${name}"
              fi
              rm -rf "$tmpdir"
            else
              echo "Warning: empty or missing favicon for ${name}"
            fi
            rm -f "${iconStorage}/${name}.ico"
          fi
        '') cfg.launchers)}
    '';
  };
  mkLauncher = name: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = with pkgs; [ gtk3 ];
    inheritPath = false;
    text = ''
      gtk-launch "${name}"
    '';
  };
  launchers = mapAttrs (name: _: mkLauncher name) cfg.launchers;
in {
  options.kirk.chromiumLaunchers = {
    enable = mkEnableOption "Chromium web application launchers";
    stateDir = mkOption {
      type = with types; nullOr path;
      default = null;
      example = "/data/.state";
      description = ''
        Stateful directory to use for the launchers, defaults to:

        `''${XDG_DATA_HOME:-$HOME/.local/state}"`
      '';
    };
    launchers = mkOption {
      type = with types; attrsOf str;
      default = {};
      description = "Attribute set mapping application names (the command to run in your terminal) to their URLs as strings.";
      example = {
        gmail = "https://mail.google.com/";
        calendar = "https://calendar.google.com/";
      };
    };
  };
  config = mkIf cfg.enable {
    home.packages = attrValues launchers;

    # Desktop entries for Pop!_OS launcher
    xdg.desktopEntries = mapAttrs (name: url: {
      name = name;
      exec = ''${pkgs.chromium}/bin/chromium --ozone-platform=x11 --user-data-dir="${stateRoot}/${name}" --class="${name}" --name="${name}" --no-first-run --app=${url}'';
      icon = "${iconStorage}/${name}.png";
      settings = { StartupWMClass = name; };
      categories = [ "Network" "WebBrowser" ];
    }) cfg.launchers;

    systemd.user.services.fetch-webapp-icons = {
      Unit = {
        Description = "Fetch chromium webapp icons";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe fetcherScript;
      };
    };

    systemd.user.timers.fetch-webapp-icons = {
      Unit.Description = "Daily timer for fetching chromium webapp icons";
      Timer = {
        OnCalendar = "daily";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}

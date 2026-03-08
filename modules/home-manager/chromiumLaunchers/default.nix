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
      else "${toString cfg.stateDir}/chromium-launchers";
  iconStorage = "${stateRoot}/icons";
  fetcherScript = pkgs.writeShellApplication {
    name = "fetch-webapp-icons";
    runtimeInputs = with pkgs; [ wget imagemagick coreutils ];
    inheritPath = false;
    text = ''
      mkdir -p "${iconStorage}"
      ${concatStringsSep "\n" (mapAttrsToList (name: url: 
        let 
          # Extract domain for the favicon service
          domain = lib.last (lib.splitString "://" url);
        in ''
          if [ ! -f "${iconStorage}/${name}.png" ]; then
            echo "Fetching icon for ${name} into ${iconStorage}..."
            wget -qO "${iconStorage}/${name}.tmp" "https://www.google.com/s2/favicons?domain=${domain}&sz=128"
            convert "${iconStorage}/${name}.tmp" "${iconStorage}/${name}.png"
            rm "${iconStorage}/${name}.tmp"
          fi
        '') cfg.launchers)}
    '';
  };
  mkLauncher = name: url: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = with pkgs; [ chromium coreutils ];
    inheritPath = false;
    text = ''
      STATE_DIR="${stateRoot}/${name}"

      mkdir -p "$STATE_DIR"
      exec chromium --user-data-dir="$STATE_DIR" --class="${name}" --no-first-run --app="${url}"
    '';
  };
  launchers = mapAttrs (name: url: mkLauncher name url) cfg.launchers;
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
    # Only the launchers go into your profile
    home.packages = attrValues launchers;

    # Desktop entries for Pop!_OS launcher
    xdg.desktopEntries = mapAttrs (name: url: {
      name = name;
      exec = name;
      icon = "${iconStorage}/${name}.png";
      settings = { StartupWMClass = name; };
      categories = [ "Network" "WebBrowser" ];
    }) cfg.launchers;

    # Run the fetcher impurely during activation
    home.activation.fetchWebappIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${fetcherScript}/bin/fetch-webapp-icons
    '';
  };
}

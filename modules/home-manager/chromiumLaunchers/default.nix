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
          # Extract domain for the favicon service
          domain = lib.last (lib.splitString "://" url);
        in ''
          if [ ! -f "${iconStorage}/${name}.png" ]; then
            wget -qO "${iconStorage}/${name}.tmp" "https://www.google.com/s2/favicons?domain=${domain}&sz=128" &&
            convert "${iconStorage}/${name}.tmp" "${iconStorage}/${name}.png" &&
            rm "${iconStorage}/${name}.tmp"
          fi
        '') cfg.launchers)}
    '';
  };
  mkLauncher = name: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = with pkgs; [ gtk3 ];
    inheritPath = false;
    text = ''
      gtk-launch ${name}
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
      exec = "${pkgs.chromium}/bin/chromium --ozone-platform=x11 --user-data-dir=${stateRoot}/${name} --class=${name} --name=${name} --no-first-run --app=${url}";
      icon = "${iconStorage}/${name}.png";
      settings = { StartupWMClass = name; };
      categories = [ "Network" "WebBrowser" ];
    }) cfg.launchers;

    # Run the fetcher impurely during activation
    home.activation.fetchWebappIcons = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${concatStringsSep "\n" (mapAttrsToList (name: _: ''
        $DRY_RUN_CMD mkdir -p "${stateRoot}/${name}"
      '') cfg.launchers)}
      $DRY_RUN_CMD ${lib.getExe fetcherScript} || echo "Warning: Failed to fetch some webapp icons."
    '';
  };
}

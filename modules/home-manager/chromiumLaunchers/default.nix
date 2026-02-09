{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.chromiumLaunchers;
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

  config = let
    mkLauncher = x:
      pkgs.writeShellApplication {
        name = x.name;
        runtimeInputs = with pkgs; [chromium];
        text = ''
          NAME=$(echo "${x.url}" | sed -E 's|https?://||g' | sed -E 's|[/.]||g')
          ${
            if cfg.stateDir == null then ''
              STATE_ROOT="''${XDG_DATA_HOME:-$HOME/.local/state}/chromium-launchers"
            ''
            else ''
              STATE_ROOT=${cfg.stateDir}/chromium-launchers
            ''
          }
          STATE_DIR="$STATE_ROOT/$NAME"

          mkdir -p "$STATE_DIR"
          nohup chromium --app="${x.url}" --user-data-dir="$STATE_DIR" > /dev/null &
        '';
      };
  in mkIf cfg.enable {
    home.packages = map mkLauncher (builtins.attrValues (builtins.mapAttrs (name: url: {inherit name url;}) cfg.launchers));
  };
}

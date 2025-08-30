{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.chromiumLaunchers;
  mkLauncher = x:
    pkgs.writeShellApplication {
      name = x.name;
      runtimeInputs = with pkgs; [chromium];
      text = ''
        NAME=$(echo "${x.url}" | sed -E 's|https?://||g' | sed -E 's|[/.]||g')
        STATE_DIR="''${XDG_DATA_HOME:-$HOME/.local/state}/chromium/$NAME"
        mkdir -p "$STATE_DIR"
        nohup chromium --app="${x.url}" --user-data-dir="$STATE_DIR" > /dev/null &
      '';
    };
in {
  options.kirk.chromiumLaunchers = {
    enable = mkEnableOption "Chromium web application launchers";
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
    home.packages = map mkLauncher (builtins.attrValues (builtins.mapAttrs (name: url: {inherit name url;}) cfg.launchers));
  };
}

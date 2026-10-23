{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.slack;
in {
  options.kirk.slack.enable = mkEnableOption "Slack as a systemd user service that restarts when it exits";

  config = mkIf cfg.enable {
    home.packages = [pkgs.slack];

    systemd.user.services.slack = {
      Unit = {
        Description = "Slack";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "${getExe pkgs.slack} --startup";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}

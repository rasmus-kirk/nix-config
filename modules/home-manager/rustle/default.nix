{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.rustle;
in {
  options.kirk.rustle = {
    enable = mkEnableOption "rustle";
  };

  config = mkIf cfg.enable {
    systemd.user.services.rustle = {
      Unit.Description = "Rustle Daemon";

      Service = {
        ExecStart = "${pkgs.lib.getExe inputs.rustle.packages.rustle}";
        Restart = "always";
        SuccessExitStatus = [0 1];
      };

      Install.WantedBy = ["multi-user.target"];
    };
  };
}

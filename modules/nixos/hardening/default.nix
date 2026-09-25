{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.hardening;
in {
  options.kirk.hardening = {
    enable = mkEnableOption "system hardening defaults";
  };

  config = mkIf cfg.enable {
    boot.tmp.cleanOnBoot = true;

    security.sudo = {
      execWheelOnly = true;
      extraConfig = ''
        Defaults timestamp_timeout=0
      '';
    };
  };
}

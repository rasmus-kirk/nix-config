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

    boot.kernel.sysctl."dev.tty.legacy_tiocsti" = 0;

    security.sudo = {
      execWheelOnly = true;
      extraConfig = ''
        Defaults timestamp_timeout=0
      '';
    };
  };
}

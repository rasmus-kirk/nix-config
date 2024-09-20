{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.ssh;
in {
  options.kirk.ssh = {
    enable = mkEnableOption "ssh with extra config";

    identityPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "The directory containing the path to the identity file.";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      extraConfig = mkIf (cfg.identityPath != null) ''
        IdentityFile ${cfg.identityPath}
      '';
    };
  };
}

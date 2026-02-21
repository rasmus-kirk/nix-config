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

    addKeysToAgent = mkOption {
      type = types.bool;
      default = false;
      description = "Whether or not to enable adding ssh keys to ssh-agent.";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        addKeysToAgent = if cfg.addKeysToAgent then "yes" else "no";
      };
      extraConfig = mkIf (cfg.identityPath != null) ''
        IdentityFile ${cfg.identityPath}
      '';
    };
  };
}

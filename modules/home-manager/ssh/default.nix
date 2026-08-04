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

    includes = mkOption {
      type = with types; listOf str;
      default = [];
      example = [ "/data/.state/ssh/remotes/*.conf" ];
      description = ''
        Paths (glob-supporting) to add as SSH `Include` directives. Lets
        per-machine host definitions live outside the nix config — the
        file just has to exist on disk at ssh time; a missing match is
        silently ignored.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        addKeysToAgent =
          if cfg.addKeysToAgent
          then "yes"
          else "no";
      };
      extraConfig = concatStringsSep "\n" (
        optional (cfg.identityPath != null) "IdentityFile ${cfg.identityPath}"
        ++ map (p: "Include ${p}") cfg.includes
      );
    };
  };
}

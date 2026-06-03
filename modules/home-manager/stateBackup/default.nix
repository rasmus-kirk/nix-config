{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.stateBackup;

  backupScript = pkgs.writeShellApplication {
    name = "state-backup";
    runtimeInputs = with pkgs; [rsync coreutils];
    inheritPath = false;
    text = ''
      # Ensure directories exist
      mkdir -p "${cfg.destDir}"

      echo "Starting state backup to ${cfg.destDir}..."

      rsync -av --delete "${cfg.sourceDir}/" "${cfg.destDir}/"

      echo "Backup completed successfully at $(date)"
    '';
  };
in {
  options.kirk.stateBackup = {
    enable = mkEnableOption "the state backup user-level timer.";

    sourceDir = mkOption {
      type = types.str;
      default = "/data/.state";
      description = "The source directory to backup.";
    };

    destDir = mkOption {
      type = types.str;
      default = "/data/.state-backup";
      description = "The destination directory for the backup.";
    };

    interval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to run the backup (Systemd OnCalendar format).";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.state-backup = {
      Unit = {
        Description = "Backup Syncthing state directory";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe backupScript;
      };
    };

    systemd.user.timers.state-backup = {
      Unit = {
        Description = "Timer for Syncthing state backup";
      };
      Timer = {
        OnCalendar = cfg.interval;
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}

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

    pulseDuration = mkOption {
      type = types.ints.unsigned;
      default = 120;
      description = "Duration of each tone in seconds.";
    };

    frequency = mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = "Frequency of the sine wave during pulses in Hz.";
    };

    amplitude = mkOption {
      type = types.float;
      default = 0.01;
      description = "Amplitude of the sine wave (e.g., 0.01 for 1%).";
    };

    minutesOfSilence = mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = "Minutes of undetected sound until the tone plays.";
    };

    debug = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether or not to enable debugging.";
      };
      interval = mkOption {
        type = types.int;
        default = 60;
        description = "Debug information interval in seconds.";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.rustle = {
      Unit = {
        Description = "Rustle Daemon";
        StartLimitIntervalSec = 10;
        StartLimitBurst = 0;
      };

      Service = {
        ExecStart = ''
          ${pkgs.lib.getExe inputs.rustle.packages.${pkgs.system}.default} \
            --pulse-duration ${builtins.toString cfg.pulseDuration} \
            --frequency ${builtins.toString cfg.frequency} \
            --amplitude ${builtins.toString cfg.amplitude} \
            --minutes-of-silence ${builtins.toString cfg.minutesOfSilence}
        '';
        Environment = lib.optionals cfg.debug.enable ["RUST_LOG=debug" "DEBUG_INTERVAL=${builtins.toString cfg.debug.interval}"];
        Restart = "always";
        RestartSec = 5; # Wait 5 seconds before restarting
        SuccessExitStatus = [0 1];
      };

      Install.WantedBy = ["multi-user.target"];
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.cec;

  python = pkgs.python3.withPackages (ps: [ps.evdev ps.typer]);
  main = "${./src}/main.py";

  settings = pkgs.writeText "cec-tv-liveness.json" (builtins.toJSON (removeAttrs cfg ["enable" "user" "replaceSuspend"]));

  sleepToTv = [
    ""
    "${pkgs.writeShellScript "sleep-to-tv-standby" ''
      ${pkgs.procps}/bin/pkill -USR1 -f ${main} || true
    ''}"
  ];
in {
  options.kirk.cec = {
    enable = mkEnableOption "the HDMI-CEC TV liveness daemon, which puts the TV in standby when idle and wakes it on input";

    user = mkOption {
      type = types.str;
      description = "User whose session runs the daemon. The user gets the `cectv` group.";
    };

    device = mkOption {
      type = types.str;
      default = "/dev/cec0";
      description = "CEC adapter device node.";
    };

    osdName = mkOption {
      type = types.str;
      default = "Desktop";
      description = "OSD name this device reports to the TV.";
    };

    idleMinutes = mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = "Minutes without a sleep key press, TV audio or a powered controller before standby.";
    };

    tvLogicalAddress = mkOption {
      type = types.int;
      default = 0;
      description = "CEC logical address of the TV.";
    };

    audioSystemLogicalAddress = mkOption {
      type = types.int;
      default = 5;
      description = ''
        CEC logical address of the AVR or soundbar that receives volume and
        mute. The TV speaker volume is not controllable over CEC.
      '';
    };

    sink = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra2";
      description = ''
        PipeWire node.name of the TV sink. The audio monitor and the
        keep-alive tone use this sink, so a change of default sink does not
        affect the TV. Null follows the default sink.
      '';
    };

    audioKeepsAwake = mkOption {
      type = types.bool;
      default = true;
      description = "Count sound on the TV sink as activity.";
    };

    replaceSuspend = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Replace system suspend, hibernate and hybrid sleep with a TV toggle,
        so a suspend request from Steam toggles the TV and the box stays on.
      '';
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Log power, RMS, idle and controller state to the journal.";
    };

    controllerVolume = {
      enable = mkEnableOption ''
        relaying TV sink volume changes to the AVR over CEC. Steam controller
        volume keys change only the system volume, so the sink is held at
        referencePercent and each change becomes CEC volume steps. Requires
        `sink`'';

      referencePercent = mkOption {
        type = types.ints.between 1 99;
        default = 75;
        description = "Percent the TV sink is held at. Must be below 100 so a volume up is visible.";
      };

      stepPercent = mkOption {
        type = types.ints.positive;
        default = 5;
        description = "TV sink percent change per CEC volume step.";
      };
    };

    keepAwake = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          While the TV is on, play a sub-audible tone after silenceMinutes of
          silence, so the speakers do not go to standby.
        '';
      };

      silenceMinutes = mkOption {
        type = types.ints.unsigned;
        default = 10;
        description = "Minutes of silence before a keep-alive pulse.";
      };

      pulseSeconds = mkOption {
        type = types.ints.unsigned;
        default = 10;
        description = "Length of a keep-alive pulse in seconds.";
      };

      amplitude = mkOption {
        type = types.float;
        default = 0.05;
        description = "Keep-alive tone amplitude, 0.0 to 1.0.";
      };

      frequency = mkOption {
        type = types.ints.unsigned;
        default = 20;
        description = "Keep-alive tone frequency in Hz.";
      };

      threshold = mkOption {
        type = types.float;
        default = 0.001;
        description = "Monitor RMS at or above this value counts as sound.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.controllerVolume.enable -> cfg.sink != null;
          message = "kirk.cec.controllerVolume requires kirk.cec.sink.";
        }
      ];

      users.groups.cectv = {};
      users.users.${cfg.user}.extraGroups = ["cectv"];

      services.udev.extraRules = ''
        SUBSYSTEM=="cec", KERNEL=="cec[0-9]*", GROUP="cectv", MODE="0660"
        SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*System Control*", GROUP="cectv", MODE="0660"
        SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*Consumer Control*", GROUP="cectv", MODE="0660"
      '';

      services.logind.settings.Login.HandleSuspendKey = "ignore";
      services.logind.settings.Login.HandleSuspendKeyLongPress = "ignore";

      environment.systemPackages = [pkgs.v4l-utils];

      systemd.user.services.cec-tv-liveness = {
        description = "HDMI-CEC TV liveness";
        after = ["pipewire.service"];
        wantedBy = ["default.target"];
        unitConfig.ConditionUser = cfg.user;
        path = with pkgs; [v4l-utils pipewire pulseaudio];
        serviceConfig = {
          ExecStart = "${python}/bin/python ${main} ${settings}";
          Restart = "always";
          RestartSec = 5;
        };
      };
    }

    (mkIf cfg.replaceSuspend {
      systemd.services.systemd-suspend.serviceConfig.ExecStart = mkForce sleepToTv;
      systemd.services.systemd-hibernate.serviceConfig.ExecStart = mkForce sleepToTv;
      systemd.services.systemd-hybrid-sleep.serviceConfig.ExecStart = mkForce sleepToTv;
    })
  ]);
}

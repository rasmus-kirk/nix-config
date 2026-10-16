{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.server;

  sensor-log = pkgs.writeShellApplication {
    name = "sensor-log";
    runtimeInputs = with pkgs; [coreutils];
    inheritPath = false;
    text = ''
      format() {
        local kind="$1" value="$2"

        case "$kind" in
          temp*) echo "$((value / 1000))C" ;;
          in*) echo "''${value}mV" ;;
          curr*) echo "''${value}mA" ;;
          power*) echo "$((value / 1000000))W" ;;
          fan*) echo "''${value}rpm" ;;
          freq*) echo "$((value / 1000000))MHz" ;;
          *) echo "$value" ;;
        esac
      }

      readings() {
        local dir="$1" chip input sensor label value

        chip=$(cat "$dir/name")
        for input in "$dir"/*_input "$dir"/power*_average; do
          value=$(cat "$input" 2>/dev/null) || continue
          sensor=$(basename "$input" | cut -d_ -f1)
          label=$(cat "$dir/''${sensor}_label" 2>/dev/null || echo "$sensor")
          echo "$chip:''${label// /_}=$(format "$sensor" "$value")"
        done
      }

      main() {
        local dir

        for dir in /sys/class/hwmon/hwmon*; do
          readings "$dir"
        done | paste -sd ' '
      }

      main
    '';
  };
in {
  options.kirk.server = {
    enable = mkEnableOption "server defaults that keep the machine up and record why it went down";

    sensorLog.enable = mkEnableOption "a hwmon reading every 30 seconds in the `sensors` journal namespace, read with `journalctl --namespace=sensors`";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # journald can crash when memory runs out; never rate-limit its restart.
      systemd.services.systemd-journald.unitConfig.StartLimitIntervalSec = 0;

      boot.kernelParams = [
        "panic=10" # Reboot after 10 seconds of kernel panic
      ];

      boot.kernel.sysctl."kernel.hardlockup_panic" = 1;

      # Forces full colors in terminal over SSH
      environment.variables = {
        COLORTERM = "truecolor";
        TERM = "xterm-256color";
      };

      services.tuptime.enable = true;
      environment.systemPackages = [pkgs.tuptime];

      services.openssh = {
        enable = true;
        openFirewall = true;
        settings.PasswordAuthentication = false;
      };
    }

    (mkIf cfg.sensorLog.enable {
      environment.etc."systemd/journald@sensors.conf".text = ''
        [Journal]
        SystemMaxUse=512M
        SyncIntervalSec=15s
      '';

      systemd.timers.sensor-log = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "30s";
          AccuracySec = "1s";
        };
      };

      systemd.services.sensor-log.serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LogNamespace = "sensors";
        ExecStart = getExe sensor-log;
      };
    })
  ]);
}

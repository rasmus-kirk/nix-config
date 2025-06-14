{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.monero;

  configFile = pkgs.writeText "monero.conf" ''
    log-file=/dev/stdout
    log-level=0
    data-dir=${cfg.dataDir}

    ${cfg.extraConfig}
  '';

  monero = pkgs.writeShellApplication {
    name = "monero";
    text = ''
      wallet_path="$HOME/media/documents/wallets/user"
      mkdir -p "$wallet_path"
      monero-wallet-cli \
        --wallet-file "$wallet_path"/user.keys \
        --log-file "$wallet_path"/log.log
    '';
  };
in {
  options.kirk.monero = {
    enable = mkEnableOption "the monero node user-level systemd-service.";

    dataDir = mkOption {
      type = types.str;
      default = "$HOME/.bitmonero";
      description = "The directory that the node uses for state.";
    };

    extraConfig = mkOption {
      type = types.str;
      default = "";
      description = "Extra configuration to pass to the node.";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.monero = {
      Unit = {
        Description = "Monero node daemon";
        StartLimitIntervalSec = 0; # Disable rate-limiting on restarts
        StartLimitBurst = 0; # Allow unlimited restart attempts
      };

      Service = {
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.monero-cli}/bin/monerod --config-file=${configFile} --data-dir=${cfg.dataDir} --non-interactive'";
        Restart = "always";
        SuccessExitStatus = [0 1];
      };

      Install.WantedBy = ["multi-user.target"];
    };

    home.packages = with pkgs; [
      monero-cli
      monero
    ];
  };
}

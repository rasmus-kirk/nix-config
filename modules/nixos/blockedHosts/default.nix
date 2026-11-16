{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.blockedHosts;
  hostsSource = config.environment.etc.hosts.source;
  secretPath = config.age.secrets.blocked-hosts.path;
in {
  options.kirk.blockedHosts = {
    enable = mkEnableOption "blocked hosts from the StevenBlack hosts list";

    file = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "../../../age/shared/blocked-hosts.age";
      description = "Agenix file with hosts lines, for example `0.0.0.0 example.com`, appended to /etc/hosts at runtime.";
    };

    blockFakenews = mkEnableOption "fake news blocking" // {default = true;};
    blockGambling = mkEnableOption "gambling blocking" // {default = true;};
    blockPorn = mkEnableOption "porn blocking" // {default = true;};
    blockSocial = mkEnableOption "social media blocking" // {default = true;};
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking.stevenBlackHosts = {
        enable = true;
        enableIPv6 = true;
        inherit (cfg) blockFakenews blockGambling blockPorn blockSocial;
      };
    }

    (mkIf (cfg.file != null) {
      age.secrets.blocked-hosts.file = cfg.file;

      environment.etc.hosts.enable = false;

      systemd.services.blocked-hosts = {
        description = "Write /etc/hosts with blocked hosts";
        wantedBy = ["multi-user.target"];
        before = ["network-pre.target" "nss-lookup.target"];
        wants = ["nss-lookup.target"];
        restartTriggers = [hostsSource cfg.file];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [pkgs.coreutils];
        script = ''
          tmp="$(mktemp /etc/.hosts.XXXXXX)"
          trap 'rm -f "$tmp"' EXIT
          cat ${hostsSource} > "$tmp"
          if [ -r ${secretPath} ]; then
            printf '\n' >> "$tmp"
            cat ${secretPath} >> "$tmp"
          else
            echo "blocked-hosts: ${secretPath} is missing, writing /etc/hosts without it" >&2
          fi
          chmod 0644 "$tmp"
          mv -f "$tmp" /etc/hosts
          trap - EXIT
        '';
      };
    })
  ]);
}

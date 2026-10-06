{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.remoteBuilds;
  dispatch = pkgs.writeShellScript "nixremote-dispatch" ''
    case "$SSH_ORIGINAL_COMMAND" in
      "nix-daemon --stdio") exec ${config.nix.package}/bin/nix-daemon --stdio ;;
      "nixos-version") exec /run/current-system/sw/bin/nixos-version ;;
      *) echo "denied" >&2; exit 1 ;;
    esac
  '';
in {
  options.kirk.remoteBuilds = {
    server = {
      enable = mkEnableOption "the locked-down `nixremote` SSH user that other machines offload Nix builds to";

      authorizedKeyFiles = mkOption {
        type = types.listOf types.path;
        default = [];
        description = "Client public keys. Must not be sk keys, because nix-daemon cannot wait for a YubiKey touch.";
      };
    };

    client = {
      enable = mkEnableOption "offloading Nix builds to the desktop";

      sshKey = mkOption {
        type = types.str;
        description = "Private key that nix-daemon uses for the SSH login. Must not be an sk key.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.server.enable {
      users.groups.nixremote = {};
      users.users.nixremote = {
        isNormalUser = true;
        hashedPassword = "!";
        group = "nixremote";
        openssh.authorizedKeys.keyFiles = cfg.server.authorizedKeyFiles;
      };
      services.openssh.extraConfig = ''
        Match User nixremote
          ForceCommand ${dispatch}
          PermitTTY no
          AllowTcpForwarding no
          AllowStreamLocalForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTunnel no
      '';
    })

    (mkIf cfg.client.enable {
      nix.distributedBuilds = true;
      nix.buildMachines = [
        {
          hostName = "desktop-builder";
          sshUser = "nixremote";
          sshKey = cfg.client.sshKey;
          systems = ["x86_64-linux"];
          protocol = "ssh-ng";
          maxJobs = 8;
          speedFactor = 2;
          supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
        }
      ];
      programs.ssh.knownHosts."desktop-builder".publicKeyFile = ../../../ssh-keys/age/desktop.pub;
      programs.ssh.extraConfig = ''
        Host desktop-builder
          HostKeyAlias desktop-builder
          HostName desktop.tailb0eb01.ts.net
          Port 6000
          User nixremote
      '';
    })
  ];
}

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kirk.remoteBuilds;
  hostName = config.networking.hostName;
  store = "ssh://desktop-builder?ssh-key=${cfg.client.sshKey}";
  prebuilt = pkgs.linkFarm "prebuilt-systems" (map (host: {
      name = host;
      path = inputs.self.nixosConfigurations.${host}.config.system.build.toplevel;
    })
    cfg.server.prebuiltHosts);
  dispatch = pkgs.writeShellScript "nixremote-dispatch" ''
    case "$SSH_ORIGINAL_COMMAND" in
      "nix-store --serve --write") exec ${config.nix.package}/bin/nix-store --serve ;;
      "nixos-version") exec /run/current-system/sw/bin/nixos-version ;;
      "latest "*)
        host=''${SSH_ORIGINAL_COMMAND#latest }
        [[ $host =~ ^[a-z0-9-]+$ ]] && readlink ${prebuilt}/"$host" || { echo "denied" >&2; exit 1; } ;;
      *) echo "denied" >&2; exit 1 ;;
    esac
  '';
  prebuiltUpgrade = pkgs.writeShellScript "nixos-prebuilt-upgrade" ''
    set -euo pipefail
    path=$(ssh -i ${cfg.client.sshKey} desktop-builder latest ${hostName})
    [[ $path == /nix/store/*-nixos-system-${hostName}-* ]] || { echo "unexpected path: $path" >&2; exit 1; }
    [[ $path != "$(readlink -f /nix/var/nix/profiles/system)" ]] || exit 0
    nix copy --no-check-sigs --from ${escapeShellArg store} "$path"
    nix build --no-link --profile /nix/var/nix/profiles/system "$path"
    "$path"/bin/switch-to-configuration boot
  '';
in {
  options.kirk.remoteBuilds = {
    server = {
      enable = mkEnableOption "the locked-down `nixremote` SSH user that other machines fetch prebuilt systems from";

      authorizedKeyFiles = mkOption {
        type = types.listOf types.path;
        default = [];
        description = "Client public keys. Must not be sk keys, because root services cannot wait for a YubiKey touch.";
      };

      prebuiltHosts = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "NixOS configurations of this flake that the server builds with its own system and serves to `latest <host>`.";
      };
    };

    client = {
      enable = mkEnableOption "the `desktop-builder` SSH host for root";

      sshKey = mkOption {
        type = types.str;
        description = "Private key that root uses for the SSH login. Must not be an sk key.";
      };

      prebuilt.enable = mkEnableOption "daily upgrades to the system that the desktop prebuilt for this host";
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
      programs.ssh.knownHosts."desktop-builder".publicKeyFile = ../../../ssh-keys/age/desktop.pub;
      programs.ssh.extraConfig = ''
        Host desktop-builder
          HostKeyAlias desktop-builder
          HostName desktop.tailb0eb01.ts.net
          Port 6000
          User nixremote
          ConnectTimeout 5
      '';
    })

    (mkIf (cfg.client.enable && cfg.client.prebuilt.enable) {
      systemd.services.nixos-prebuilt-upgrade = {
        description = "Upgrade to the system prebuilt on the desktop";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [config.nix.package config.programs.ssh.package pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = "${config.programs.ssh.package}/bin/ssh -i ${cfg.client.sshKey} desktop-builder nixos-version";
          ExecStart = prebuiltUpgrade;
        };
      };
      systemd.timers.nixos-prebuilt-upgrade = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    })
  ];
}

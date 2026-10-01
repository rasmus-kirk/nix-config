{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.box;
  boxHome = "/home/${cfg.user}";
  boxTokenDir = "${boxHome}/.secret/tokens-read-only";
in {
  options.kirk.box = {
    enable = mkEnableOption "bubblewrap sandbox";

    user = mkOption {
      type = types.str;
      default = "user";
      description = "User account inside the box.";
    };

    homeManagerPackage = mkOption {
      type = types.package;
      example = literalExpression "inputs.self.homeConfigurations.sandbox.activationPackage";
      description = "The box's home-manager generation, built by the host.";
    };

    yubiHandle = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/data/.secret/ssh/id_ed25519_yubi";
      description = "YubiKey handle for signing in the box. Used only with `--yubi`.";
    };

    tokenDir = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/data/.secret/tokens-read-only";
      description = "Directory of read-only tokens, mounted at ~/.secret/tokens-read-only in the box. Used only with `--tokens`.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "box";
        runtimeInputs = with pkgs; [argc bubblewrap coreutils gnugrep];
        inheritPath = false;
        text = ''
          # @describe Bubblewrap sandbox.
          # @meta version 0.6.0
          # @flag --net                 Share the host's network.
          # @flag --rw                  Bind $PWD read-write (default is read-only).
          # @flag --yubi                Expose the YubiKey and its SSH key handle.
          # @flag --claude              Bind the host's Claude Code state (~/.claude).
          # @flag --tokens              Mount the read-only tokens in tokenDir.

          main() {
            local args=(
              --tmpfs /
              --ro-bind /nix /nix
              --bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
              --proc /proc
              --dev /dev
              --dir /tmp
              --ro-bind-try /etc/passwd /etc/passwd
              --ro-bind-try /etc/group /etc/group
              --ro-bind-try /etc/resolv.conf /etc/resolv.conf
              --ro-bind-try /etc/localtime /etc/localtime
              --symlink ${pkgs.bash}/bin/sh /bin/sh
              --symlink ${pkgs.coreutils}/bin/env /usr/bin/env
              --dir ${boxHome}
              --unshare-ipc
              --unshare-pid
              --unshare-uts
              --unshare-cgroup
              --hostname box
              --die-with-parent
              --clearenv
              --setenv PATH ${boxHome}/.nix-profile/bin
              --setenv HOME ${boxHome}
              --setenv USER ${cfg.user}
              --setenv LOGNAME ${cfg.user}
              --setenv SHELL ${boxHome}/.nix-profile/bin/zsh
              --setenv NIX_REMOTE daemon
              --setenv NIX_SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              --setenv SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              --setenv BOX 1
              --setenv TERM "''${TERM:-xterm-256color}"
              --setenv COLORTERM "''${COLORTERM:-truecolor}"
              --setenv LANG C.UTF-8
              --chdir "$PWD"
            )

            if [ "''${argc_net:-0}" != 1 ]; then
              args+=(--unshare-net)
            fi

            # Add yubikeys if enabled.
            if [ "''${argc_yubi:-0}" = 1 ]; then
              local h
              for h in /sys/class/hidraw/hidraw*; do
                grep -q ':00001050:' "$h/device/uevent" 2>/dev/null || continue
                args+=(--dev-bind-try "/dev/''${h##*/}" "/dev/''${h##*/}")
              done
              ${optionalString (cfg.yubiHandle != null) ''
                args+=(--ro-bind-try ${cfg.yubiHandle} ${boxHome}/.ssh/id_ed25519_yubi)
                args+=(--ro-bind-try ${cfg.yubiHandle}.pub ${boxHome}/.ssh/id_ed25519_yubi.pub)
              ''}
            fi

            # Mount Claude state dir.
            if [ "''${argc_claude:-0}" = 1 ]; then
              mkdir -p ${config.home.homeDirectory}/.claude
              if [ ! -e ${config.home.homeDirectory}/.claude.json ]; then
                echo '{}' > ${config.home.homeDirectory}/.claude.json
              fi
              args+=(--bind ${config.home.homeDirectory}/.claude ${boxHome}/.claude)
              args+=(--bind ${config.home.homeDirectory}/.claude.json ${boxHome}/.claude.json)
            fi

            if [ "''${argc_tokens:-0}" = 1 ]; then
              ${optionalString (cfg.tokenDir != null) ''
                args+=(--ro-bind-try ${cfg.tokenDir} ${boxTokenDir})
              ''}
              ${optionalString (cfg.tokenDir == null) ''
                echo "box: --tokens needs kirk.box.tokenDir" >&2
                exit 1
              ''}
            fi

            mkdir -p ${config.xdg.cacheHome}/box/nix
            args+=(--bind ${config.xdg.cacheHome}/box/nix ${boxHome}/.cache/nix)

            if [ "''${argc_rw:-0}" = 1 ]; then
              # Read-write mode.
              args+=(--bind-try "$PWD" "$PWD")
            else
              # Read-only mode.
              if [ -f "$PWD/.envrc" ]; then
                mkdir -p "$PWD/.direnv"
              fi
              args+=(--ro-bind-try "$PWD" "$PWD")
              [ -d "$PWD/.direnv" ] && args+=(--tmpfs "$PWD/.direnv")
              [ -d "$PWD/.devenv" ] && args+=(--tmpfs "$PWD/.devenv")
            fi

            exec bwrap "''${args[@]}" ${pkgs.writeShellScript "box-init" ''
              set -e
              export HOME_MANAGER_BACKUP_EXT=backup
              ${cfg.homeManagerPackage}/activate
              exec ${boxHome}/.nix-profile/bin/zsh
            ''}
          }

          eval "$(argc --argc-eval "$0" "$@")"
        '';
      })
    ];
  };
}

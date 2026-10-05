{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kirk.nixosScripts;
  remoteStateDir = "/var/lib/nos-remotes";
  rebuildFlags = "--show-trace ${optionalString (!cfg.pure) "--impure"} --option warn-dirty false --flake ${escapeShellArg "${cfg.configDir}#${cfg.machine}"}";
  staleCheck = pkgs.writeShellApplication {
    name = "nos-stale-check";
    runtimeInputs = with pkgs; [argc coreutils];
    inheritPath = false;
    text = ''
      # @describe Warn when the pinned nixpkgs of this machine or a remote is older than maxNixpkgsAge.
      # @meta version 0.1.0

      check() {
        local name="$1" pinnedAt="$2"
        local staleAt=$((pinnedAt + ${toString cfg.maxNixpkgsAge} * 24 * 60 * 60))
        local warning='\033[1;37m[\033[1;33mWARNING\033[1;37m]:\033[0m'

        [ "$(date +%s)" -gt "$staleAt" ] || return 0
        echo -e "$warning $name nixpkgs is from $(date -d "@$pinnedAt" +%F), which is older than ${toString cfg.maxNixpkgsAge} days, please run upgrade"
      }

      main() {
        local remotes=(${escapeShellArgs (attrNames cfg.remotes)})
        local name version pinnedAt

        check ${cfg.machine} ${toString inputs.nixpkgs.lastModified}

        for name in "''${remotes[@]}"; do
          version=$(cat "${remoteStateDir}/$name" 2>/dev/null) || continue
          pinnedAt=$(date -d "$(echo "$version" | cut -d. -f3)" +%s 2>/dev/null) || continue
          check "$name" "$pinnedAt"
        done
      }

      eval "$(argc --argc-eval "$0" "$@")"
    '';
  };
  nos = pkgs.writeShellApplication {
    name = "nos";
    runtimeInputs = with pkgs; [argc fzf git coreutils gnugrep];
    inheritPath = true;
    text = ''
      # @describe Manage the NixOS configuration of ${cfg.machine}.
      # @meta version 0.1.0

      info() {
        echo -e "\033[1;37m[NOS-INFO]:\033[0m $*"
      }

      error() {
        echo -e "\033[1;37m[\033[1;31mNOS-ERROR\033[1;37m]:\033[0m $*" >&2
      }

      # @cmd Rebuild and switch to the NixOS configuration.
      rebuild() {
        info "Rebuilding NixOS configuration..."
        git -C "${cfg.configDir}" add .
        sudo nixos-rebuild switch ${rebuildFlags}
      }

      # @cmd Update, rebuild and garbage collect.
      upgrade() {
        update
        rebuild
        garbage-collect
      }

      # @cmd Show the NixOS configuration options.
      options() {
        man configuration.nix
      }

      # @cmd Delete generations older than ${toString cfg.garbageCollectionDays} days and optimise the nix store.
      garbage-collect() {
        info "Garbage collecting..."
        sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than ${toString cfg.garbageCollectionDays}d
        sudo nix store gc
        sudo nix store optimise
      }

      # @cmd Update the flake inputs.
      update() {
        info "Updating flake inputs..."
        nix flake update --flake "${cfg.configDir}" --no-warn-dirty
      }

      # @cmd Switch to a generation picked with fzf.
      rollback() {
        local gen
        gen=$(nixos-rebuild list-generations | fzf --reverse | grep -oP "^\s*\K\d+")
        info "Activating NixOS generation $gen..."
        sudo "/nix/var/nix/profiles/system-$gen-link/bin/switch-to-configuration" switch
      }

      # @cmd Build the NixOS configuration without switching to it.
      test() {
        cd "$(mktemp -d)"
        info "Building the test configuration to \"$PWD\"..."
        git -C "${cfg.configDir}" add .
        nixos-rebuild build ${rebuildFlags}
      }

      if [[ $EUID -eq 0 ]]; then
        error "Do not run nos as root, it calls sudo itself."
        exit 1
      fi

      eval "$(argc --argc-eval "$0" "$@")"
    '';
  };
in {
  options.kirk.nixosScripts = {
    enable = mkEnableOption ''
      NixOS scripts

      Required options:
      - `machine`
    '';

    machine = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "REQUIRED! The machine to run on.";
    };

    configDir = mkOption {
      type = types.path;
      default = "/etc/nixos";
      description = "Path to the nixos configuration.";
    };

    extraNixOptions = mkOption {
      type = types.bool;
      default = false;
      description = "Apply opinionated nix defaults.";
    };

    pure = mkOption {
      type = types.bool;
      default = true;
      description = "Only allow pure builds.";
    };

    maxNixpkgsAge = mkOption {
      type = types.int;
      default = 7;
      description = "Warn when the pinned nixpkgs of this machine or a remote is older than this many days.";
    };

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Run `nos-stale-check` in new zsh shells of all home-manager users.";
    };

    remotes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            description = "SSH host that root fetches `nixos-version` from.";
          };
          sshKey = mkOption {
            type = types.str;
            description = "Private key for the SSH login. Must not be an sk key.";
          };
        };
      });
      default = {};
      description = "Remotes whose nixpkgs age `nos-stale-check` reports. A systemd timer fetches each one every 15 minutes.";
    };

    garbageCollectionDays = mkOption {
      type = types.int;
      default = 30;
      description = "How old in days a NixOS generation has to be in order for it to be garbage collected.";
    };
  };

  config = mkIf cfg.enable {
    nix = mkIf cfg.extraNixOptions {
      # Use latest nix version
      package = pkgs.nixVersions.latest;
      channel.enable = false;
      settings = {
        # Force this, even if nix is installed through the official installer
        experimental-features = ["nix-command" "flakes"];
        download-buffer-size = 500000000; # 500 MB
        # Faster builds
        cores = 0;
        # Return more information when errors happen
        show-trace = true;
        # Use the pinned nixpkgs version that is already used, when using `nix-shell package`
        nix-path = ["nixpkgs=${inputs.nixpkgs}"];
      };
      # Use the pinned nixpkgs version that is already used, when using `nix shell nixpkgs#package`
      registry.nixpkgs = {
        from = {
          id = "nixpkgs";
          type = "indirect";
        };
        flake = inputs.nixpkgs;
      };
    };

    environment.systemPackages = [
      nos
      staleCheck
    ];

    home-manager.sharedModules = mkIf cfg.enableZshIntegration [
      ({config, ...}: {
        programs.zsh.initContent = mkIf config.programs.zsh.enable "${staleCheck}/bin/nos-stale-check";
      })
    ];

    systemd.services = mapAttrs' (name: remote:
      nameValuePair "nos-remote-${name}" {
        description = "Fetch the NixOS version of ${name}";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [config.programs.ssh.package];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nos-remotes";
        };
        script = ''
          version=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -i ${remote.sshKey} ${remote.host} nixos-version)
          echo "$version" > "$STATE_DIRECTORY/${name}.tmp"
          mv "$STATE_DIRECTORY/${name}.tmp" "$STATE_DIRECTORY/${name}"
        '';
      })
    cfg.remotes;

    systemd.timers = mapAttrs' (name: _:
      nameValuePair "nos-remote-${name}" {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "15min";
        };
      })
    cfg.remotes;
  };
}

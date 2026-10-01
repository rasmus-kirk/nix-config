{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kirk.nixosScripts;
  nos = pkgs.writeShellApplication {
    name = "nos";
    runtimeInputs = with pkgs; [fzf git coreutils gnugrep];
    inheritPath = true;
    text = ''
      command="''${1:-}"

      NC='\033[0m'
      BRED='\033[1;31m'
      BWHITE='\033[1;37m'

      NOS_INFO="''${BWHITE}[NOS-INFO]:''${NC}"
      NOS_ERROR="''${BWHITE}[''${BRED}NOS-ERROR''${BWHITE}]:''${NC}"

      # Auto-escalate to root
      if [ "$EUID" -ne 0 ]; then
        echo -e "$NOS_INFO Escalating privileges..."
        exec sudo "$0" "$@"
      fi

      ORIG_USER="''${SUDO_USER:-root}"

      if [ -z "$command" ]; then
        echo "Usage: nos <command>"
        echo "Commands: rebuild, upgrade, options, garbage-collect, update, rollback, test"
        exit 1
      fi

      update() {
        echo -e "$NOS_INFO Updating packages... \n"
        sudo -u "$ORIG_USER" nix flake update --flake "${cfg.configDir}" --no-warn-dirty
      }

      rebuild() {
        echo -e "$NOS_INFO Rebuilding NixOS configuration... \n"

        pushd "${cfg.configDir}" > /dev/null
        sudo -u "$ORIG_USER" git add .
        nixos-rebuild switch \
          --show-trace ${
        if !cfg.pure
        then "--impure"
        else ""
      } \
          --option warn-dirty false \
          --flake .#${cfg.machine}
        popd > /dev/null
      }

      garbage_collect() {
        echo -e "$NOS_INFO Garbage collecting... \n"
        nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 30d
        nix store gc
        nix store optimise
      }

      rollback() {
        gen=$(nixos-rebuild list-generations | fzf --reverse)
        if [ -z "$gen" ]; then
          echo -e "$NOS_ERROR No generation selected. Aborting."
          exit 1
        fi
        genId=$(echo "$gen" | grep -oP "^\s*\K\d+")

        echo -e "$NOS_INFO Activating NixOS generation $genId..."
        /nix/var/nix/profiles/system-"$genId"-link/bin/switch-to-configuration switch
      }

      case "$1" in
        rebuild)
          rebuild
          ;;
        upgrade)
          echo -e "$NOS_INFO Upgrading NixOS packages... \n"
          update &&
          rebuild &&
          garbage_collect
          ;;
        options)
          man configuration.nix
          ;;
        garbage-collect)
          garbage_collect
          ;;
        update)
          update
          ;;
        rollback)
          rollback
          ;;
        test)
          tmpdir=$(mktemp -d)
          echo -e "$NOS_INFO Building the test configuration to \"$tmpdir\"... \n"

          pushd "${cfg.configDir}" > /dev/null
          sudo -u "$ORIG_USER" git add .
          popd > /dev/null

          pushd "$tmpdir" > /dev/null
          nixos-rebuild build --show-trace --impure --flake "${cfg.configDir}#${cfg.machine}"
          popd > /dev/null
          ;;
        *)
          echo -e "$NOS_ERROR Unknown command: $1"
          echo "Valid commands are: rebuild, upgrade, options, garbage-collect, rollback, update, test"
          exit 1
          ;;
      esac
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
      default = false;
      description = "Only allow pure builds.";
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
      # Use the pinned nixpkgs version that is already used, when using `nix-shell package`
      nixPath = ["nixpkgs=${inputs.nixpkgs}"];
      settings = {
        # Force this, even if nix is installed through the official installer
        experimental-features = ["nix-command" "flakes"];
        download-buffer-size = 500000000; # 500 MB
        # Faster builds
        cores = 0;
        # Return more information when errors happen
        show-trace = true;
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
    ];
  };
}

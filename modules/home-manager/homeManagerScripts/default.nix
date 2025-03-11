{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeManagerScripts;
  configDir =
    if (cfg.configDir != null)
    then cfg.configDir
    else "${config.xdg.configHome}/home-manager";

  hm = pkgs.writeShellApplication {
    name = "hm";
    runtimeInputs = with pkgs; [fzf git];
    text = ''
      command="''${1:-}"
      # Check if a parameter is provided
      if [ -z "$command" ]; then
        echo "Usage: hm <command>"
        echo ""
        echo "Commands:"
        echo "  rebuild           Rebuild the Home Manager configuration."
        echo "  upgrade           Upgrade Home Manager packages. Note that this also rebuilds the configuration."
        echo "  options           Shows available Home Manager configuration options."
        echo "  garbage-collect   Garbage collects, freeing up unused hard drive space allocated to unused Nix packages."
        echo "  update            Updating Nix flake inputs. This updates packages for the next rebuild..."
        echo "  test              Test the Home Manager configuration."
        echo "  rollback          Roll back to the previous configuration."
        echo ""
        echo "Garbage collecting will:"
        echo "- Delete Home Manager configurations and nix profiles older than 30 days"
        echo "- Delete unused packages in the Nix store"
        echo "- Optimize the Nix store, by replacing identical files in the store by hard links"
        exit 1
      fi

      update() {
        echo "[HM-INFO]: Updating packages for the next rebuild, by updating the Nix flake inputs..."
        echo ""
        nix flake update --flake ${configDir}
      }

      rebuild() {
        echo "[HM-INFO]: Rebuilding Home Manager configuration..."
        echo ""
        pushd "${configDir}"
        git add .
        home-manager switch -b backup --flake .#${cfg.machine}
        popd
      }

      garbage_collect() {
        echo "[HM-INFO]: Garbage collecting the Nix store..."
        echo ""
        home-manager expire-generations '-30 days'
        nix profile wipe-history --older-than 30d
        nix store gc
        nix store optimise
      }

      rollback() {
        gen=$(home-manager generations | grep -P "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | fzf)
        genPath=$(echo "$gen" | grep -oP "/nix/store/.*")
        genId=$(echo "$gen" | grep -oP "(?<=id )\d+")

        if [ -z "$gen" ]; then
          echo "[HM-ERROR]: No generation selected. Aborting."
          exit 1
        fi

        echo "[HM-INFO]: Activating generation $genId:"
        "$genPath"/activate
      }

      # Handle the command
      case "$1" in
        rebuild)
          rebuild
          ;;
        upgrade)
          echo "[HM-INFO]: Upgrading Home Manager packages..."
          echo ""
          update &&
          rebuild &&
          garbage_collect
          ;;
        options)
          man home-configuration.nix
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
          tmpdir=$(mktemp -d) &&
          echo "[HM-INFO]: Building the test configuration to \"$tmpdir\"..." &&
          cd "$tmpdir" &&
          home-manager build --show-trace --flake ${configDir}#${cfg.machine}
          ;;
        *)
          echo "[HM-ERROR]: Unknown command: $1"
          echo "Valid commands are: rebuild, upgrade, options, garbage-collect, rollback, update, test"
          exit 1
          ;;
      esac
    '';
  };
in {
  options.kirk.homeManagerScripts = {
    enable = mkEnableOption ''
      Home manager scripts. Gives access to command-line scripts that make
      managing home-manager easier. These scripts are lean bash scripts that
      compose a couple of nix and home-manager commands:

      - `hm rebuild`: Rebuild the Home Manager configuration."
      - `hm upgrade`: Upgrade Home Manager packages. Note that this also rebuilds the configuration."
      - `hm options`: Shows available Home Manager configuration options."
      - `hm garbage-collect`: Garbage collects, freeing up unused hard drive space allocated to unused Nix packages."
      - `hm update`: Updating Nix flake inputs. This updates packages for the next rebuild..."
      - `hm test`: Test the Home Manager configuration."
      - `hm rollback`: Roll back to the previous configuration."
    '';

    configDir = mkOption {
      type = types.nullOr types.path;
      # modules are evaluated as follows: imports, options, config
      # you don't want to refer to config. from options as they haven't been evaluated yet.
      default = null;
      description = ''
        Path to the home-manager configuration. If not set, will default to:
        `''${config.xdg.configHome}/home-manager`.
      '';
    };

    machine = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "**REQUIRED!** Path to the home-manager configuration.";
    };

    disableNews = mkOption {
      type = types.nullOr types.bool;
      default = true;
      description = "Disable annoying home-manager news on rebuild.";
    };
  };

  config = mkIf cfg.enable {
    # Disable home manager news
    news = mkIf cfg.disableNews {
      display = "silent";
      json = lib.mkForce {};
      entries = lib.mkForce [];
    };

    nix = {
      # TODO: This may be necessary?
      channels = let nixpkgs = inputs.nixpkgs; in {inherit nixpkgs;};
      settings = {
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

    home.packages = [
      hm
    ];
  };
}

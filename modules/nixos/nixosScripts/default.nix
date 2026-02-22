{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.nixosScripts;

  nos = pkgs.writeShellApplication {
    name = "nos";
    runtimeInputs = with pkgs; [fzf git dateutils];
    text = ''
      command="''${1:-}"

      NC='\033[0m'               # No Color

      # Bold
      BRED='\033[1;31m'          # Red
      BYELLOW='\033[1;33m'       # Yellow
      BWHITE='\033[1;37m'        # White

      NOS_INFO="''${BWHITE}[NOS-INFO]:''${NC}"
      NOS_WARNING="''${BWHITE}[''${BYELLOW}NOS-WARNING''${BWHITE}]:''${NC}"
      NOS_ERROR="''${BWHITE}[''${BRED}NOS-ERROR''${BWHITE}]:''${NC}"

      # Must run as root
      if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
      fi

      # Check if a parameter is provided
      if [ -z "$command" ]; then
        echo "Usage: nos <command>"
        echo ""
        echo "Commands:"
        echo "  rebuild           Rebuild the NixOS configuration."
        echo "  upgrade           Upgrade NixOS packages. Note that this also rebuilds the configuration."
        echo "  options           Shows available NixOS configuration options."
        echo "  garbage-collect   Garbage collects, freeing up unused hard drive space allocated to unused Nix packages."
        echo "  update            Updating Nix flake inputs. This updates packages for the next rebuild..."
        # echo "  test              Test the NixOS configuration."
        # echo "  rollback          Roll back to the previous configuration."
        echo ""
        echo "Garbage collecting will:"
        echo "- Delete NixOS configurations and nix profiles older than 30 days"
        echo "- Delete unused packages in the Nix store"
        echo "- Optimize the Nix store, by replacing identical files in the store by hard links"
        exit 1
      fi

      update() {
        echo -e "$NOS_INFO Updating packages for the next rebuild, by updating the Nix flake inputs... \n"
        nix flake update --flake ${cfg.configDir} --no-warn-dirty
      }

      rebuild() {
        echo -e "$NOS_INFO Rebuilding NixOS configuration... \n"

        # Remind to upgrade if 30 days has passed since last upgrade
        NOS_DIR=''${XDG_CACHE_HOME:-"$HOME/.cache"}/hm
        if [ ! -f "$NOS_DIR/last-update" ]; then
          echo -e "$NOS_WARNING Could not determine last full upgrade, please run \"nos upgrade\""
        else
          TODAY=$(date -u '+%Y-%m-%d')
          LAST_UPDATE=$(cat "$NOS_DIR/last-update" || date --date="-31 day" -u '+%Y-%m-%d')
          DATE_DIFF=$(ddiff "$TODAY" "$LAST_UPDATE")
          if [ "$DATE_DIFF" -gt 30 ]; then
            echo -e "$NOS_WARNING Last full upgrade was $DATE_DIFF days ago, please run \"nos upgrade\""
          fi
        fi

        pushd "${cfg.configDir}" > /dev/null
        ls
        git add .
        nixos-rebuild switch --show-trace --impure --flake ${cfg.configDir}#${cfg.machine}
        popd > /dev/null
      }

      garbage_collect() {
        echo -e "$NOS_INFO Garbage collecting the Nix store... \n"
        nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 30d
        nix store gc &&
        nix store optimise
      }

      # rollback() {
      #   gen=$(home-manager generations | grep -P "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | fzf)
      #   genPath=$(echo "$gen" | grep -oP "/nix/store/.*")
      #   genId=$(echo "$gen" | grep -oP "(?<=id )\d+")

      #   if [ -z "$gen" ]; then
      #     echo -e "$NOS_ERROR No generation selected. Aborting."
      #     exit 1
      #   fi

      #   echo -e "$NOS_INFO Activating generation $genId:"
      #   "$genPath"/activate
      # }

      # Handle the command
      case "$1" in
        rebuild)
          rebuild
          ;;
        upgrade)
          echo -e "$NOS_INFO Upgrading NixOS packages... \n"
          update &&
          rebuild &&
          garbage_collect

          # Log upgrade date
          NOS_DIR=''${XDG_CACHE_HOME:-"$HOME/.cache"}/hm
          mkdir -p "$NOS_DIR"
          date -u '+%Y-%m-%d' > "$NOS_DIR/last-update"
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
        # rollback)
        #   rollback
        #   ;;
        # test)
        #   tmpdir=$(mktemp -d) &&
        #   echo -e "$NOS_INFO Building the test configuration to \"$tmpdir\"... \n" &&
        #   cd "$tmpdir" &&
        #   home-manager build --show-trace --flake ${cfg.configDir}#${cfg.machine}
        #   ;;
        *)
          echo -e "$NOS_ERROR Unknown command: $1 \n"
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
    environment.systemPackages = [
      nos
    ];
  };
}

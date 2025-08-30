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
    runtimeInputs = with pkgs; [fzf git dateutils];
    text = ''
      command="''${1:-}"

      NC='\033[0m'               # No Color

      # Regular Colors
      #BLACK='\033[0;30m'        # Black
      #RED='\033[0;31m'          # Red
      #GREEN='\033[0;32m'        # Green
      #YELLOW='\033[0;33m'       # Yellow
      #BLUE='\033[0;34m'         # Blue
      #PURPLE='\033[0;35m'       # Purple
      #CYAN='\033[0;36m'         # Cyan
      #WHITE='\033[0;37m'        # White

      # Bold
      #BBLACK='\033[1;30m'       # Black
      BRED='\033[1;31m'          # Red
      #BGREEN='\033[1;32m'       # Green
      BYELLOW='\033[1;33m'       # Yellow
      #BBLUE='\033[1;34m'        # Blue
      #BPURPLE='\033[1;35m'      # Purple
      #BCYAN='\033[1;36m'        # Cyan
      BWHITE='\033[1;37m'        # White

      HM_INFO="''${BWHITE}[HM-INFO]:''${NC}"
      HM_WARNING="''${BWHITE}[''${BYELLOW}HM-WARNING''${BWHITE}]:''${NC}"
      HM_ERROR="''${BWHITE}[''${BRED}HM-ERROR''${BWHITE}]:''${NC}"

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
        echo -e "$HM_INFO Updating packages for the next rebuild, by updating the Nix flake inputs... \n"
        nix flake update --flake ${configDir} --no-warn-dirty
      }

      rebuild() {
        echo -e "$HM_INFO Rebuilding Home Manager configuration... \n"

        HM_DIR=''${XDG_CACHE_HOME:-"$HOME/.cache"}/hm
        if [ ! -f "$HM_DIR/last-update" ]; then
          echo -e "$HM_WARNING Could not determine last full upgrade, please run \"hm upgrade\""
        else
          TODAY=$(date -u '+%Y-%m-%d')
          LAST_UPDATE=$(cat "$HM_DIR/last-update" || date --date="-31 day" -u '+%Y-%m-%d')
          DATE_DIFF=$(ddiff "$TODAY" "$LAST_UPDATE")
          if [ "$DATE_DIFF" -gt 30 ]; then
            echo -e "$HM_WARNING Last full upgrade was $DATE_DIFF days ago, please run \"hm upgrade\""
          fi
        fi

        MIMEAPPS_LIST="$HOME/.config/mimeapps.list.backup"
        if [ -f "$MIMEAPPS_LIST" ]; then
          echo -e "$HM_INFO trashing $MIMEAPPS_LIST..."
          trash-put "$MIMEAPPS_LIST"
        fi

        pushd "${configDir}" > /dev/null
        git add .
        home-manager switch -b backup --flake .#${cfg.machine} --option warn-dirty false
        popd > /dev/null
      }

      garbage_collect() {
        echo -e "$HM_INFO Garbage collecting the Nix store... \n"
        home-manager expire-generations '-30 days'
        nix profile wipe-history --older-than 30d --no-warn-dirty
        nix store gc --no-warn-dirty
        nix store optimise --no-warn-dirty
      }

      rollback() {
        gen=$(home-manager generations | grep -P "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | fzf)
        genPath=$(echo "$gen" | grep -oP "/nix/store/.*")
        genId=$(echo "$gen" | grep -oP "(?<=id )\d+")

        if [ -z "$gen" ]; then
          echo -e "$HM_ERROR No generation selected. Aborting."
          exit 1
        fi

        echo -e "$HM_INFO Activating generation $genId:"
        "$genPath"/activate
      }

      # Handle the command
      case "$1" in
        rebuild)
          rebuild
          ;;
        upgrade)
          echo -e "$HM_INFO Upgrading Home Manager packages... \n"
          update &&
          rebuild &&
          garbage_collect

          # Log upgrade date
          HM_DIR=''${XDG_CACHE_HOME:-"$HOME/.cache"}/hm
          mkdir -p "$HM_DIR"
          date -u '+%Y-%m-%d' > "$HM_DIR/last-update"
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
          echo -e "$HM_INFO Building the test configuration to \"$tmpdir\"... \n" &&
          cd "$tmpdir" &&
          home-manager build --show-trace --flake ${configDir}#${cfg.machine}
          ;;
        *)
          echo -e "$HM_ERROR Unknown command: $1 \n"
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

    extraNixOptions = mkEnableOption "Enable extra nix options.";
  };

  config = mkIf cfg.enable {
    # Disable home manager news
    news = mkIf cfg.disableNews {
      display = "silent";
      json = lib.mkForce {};
      entries = lib.mkForce [];
    };

    nix = mkIf cfg.extraNixOptions {
      # Use latest nix version
      package = pkgs.nixVersions.latest;
      # Use the pinned nixpkgs version that is already used, when using `nix-shell package`
      channels = let nixpkgs = inputs.nixpkgs; in {inherit nixpkgs;};
      settings = {
        #download-buffer-size = 500000000; # 500 MB
        # Force this, even if nix is installed through the official installer
        experimental-features = ["nix-command" "flakes"];
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

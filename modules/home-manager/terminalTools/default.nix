{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.terminalTools;
  toolsDescription = ''
    Terminal tools to make your life easier. The installed packages are:

    - terminal-tools: Displays this message
    - batman: Pretty Man Pages
    - btop: Task Manager
    - dust: Pretty du
    - duf: Pretty df
    - eza: Pretty ls
    - fd: Find Files
    - jq: JSON Parser
    - rig: Random Identities for Privacy
    - ag: Search in Files
    - tldr: TLDR for CLI Commands
    - trash-cli: Trash Files in Terminal
      - trash-put: Trash file or directory
      - trash-list: List trashed files
      - trash-restore: Restore trashed files
      - trash-empty: Delete trashed files
      - trash-rm: Removes files matching a pattern from the trash can
    - tree: View Directory as Tree

    The option enableZshIntegration yields the following helper commands:
    - help <command>: Runs `<command> --help`, but prettier
    - fif <string>: Finds finds that <string> recursively in directory
    - ll: Pretty ll
    - lh: Pretty lh
  '';
  toolsDescriptionFile = pkgs.writeText "terminal-tools-help" toolsDescription;
  toolsDescriptionPkg = pkgs.writeShellApplication {
    name = "terminal-tools";
    text = "cat ${toolsDescriptionFile}";
  };
in {
  options.kirk.terminalTools = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = toolsDescription;
    };

    theme = mkOption {
      type = types.str;
      default = "gruvbox-dark";
      description = "What syntax highlighting colorscheme to use.";
    };

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable zsh integration for bat.";
    };

    autoUpdateTealdeer = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-update tealdeer.";
    };

    trashCleaner = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the trash-cli cleanup script";
      };
      persistance = mkOption {
        type = types.number;
        default = 30;
        description = "How many days a file stays in trash before getting cleaned up.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      fif() {
        if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
        rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
      }

      # bat
      alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
      alias man='batman'
      alias bathelp='bat --plain --language=help'
      help() {
        "$@" --help 2>&1 | bathelp
      }

      # exa
      alias ll="eza --icons --long"
      alias lh="eza --icons --long --all"
    '';

    systemd.user = mkIf cfg.trashCleaner.enable {
      timers = {
        trashCleaner = {
          Unit.Description = "Gets a japanese word from the Jiten dictionary";

          Timer = {
            OnCalendar = "daily";
            Persistent = "true"; # Run service immediately if last window was missed
            RandomizedDelaySec = "1h"; # Run service OnCalendar +- 1h
          };

          Install.WantedBy = ["timers.target"];
        };
      };

      services = {
        trashCleaner = {
          Unit.Description = "Updates the daily japanese word";

          Service = {
            ExecStart = "${pkgs.trash-cli}/bin/trash-empty -fv ${toString cfg.trashCleaner.persistance}";
            Type = "oneshot";
          };
        };
      };
    };

    programs.tealdeer = {
      enable = true;
      settings = {
        auto_update = cfg.autoUpdateTealdeer;
        auto_update_interval_hours = 24;
      };
    };

    programs.bat = {
      enable = true;
      config.theme = cfg.theme;
    };

    home.packages = with pkgs; [
      toolsDescriptionPkg # Helper for remembering the tools
      bat-extras.batman # Pretty Man Pages
      ripgrep # Faster, better grep
      btop # Task Manager
      du-dust # Pretty du
      duf # Pretty df
      eza # Pretty ls
      fd # Find Files
      jq # JSON Parser
      rig # Random Identities for Privacy
      silver-searcher # Search in Files
      tealdeer # TLDR for CLI Commands
      trash-cli # Trash Files in Terminal
      tree # View Directory as Tree
    ];
  };
}

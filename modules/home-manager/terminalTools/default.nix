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
    - bat: Pretty cat with syntax highlighting
    - batman: Pretty Man Pages
    - btop: Task Manager
    - dust: Pretty du for seeing disk usage
    - duf: Pretty df
    - eza: Pretty ls
    - fd: Find Files
    - fzf: Search text
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

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable zsh integration for bat and fzf.";
    };

    tealdeer.autoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-update tealdeer.";
    };

    bat.theme = mkOption {
      type = types.str;
      default = "gruvbox-dark";
      description = "What syntax highlighting colorscheme to use.";
    };

    fzf.colorscheme = mkOption {
      type = types.attrs;
      default = config.kirk.gruvbox.colorscheme;
      description = "A colorscheme attribute set.";
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

      # eza
      alias ll="eza --icons --long"
      alias lh="eza --icons --long --all"
    '';

    systemd.user = mkIf cfg.trashCleaner.enable {
      timers = {
        trashCleaner = {
          Unit.Description = "Timer for trash-cli cleaner";

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
          Unit.Description = "Cleans trash-cli trash bin";

          Service = {
            ExecStart = "${pkgs.trash-cli}/bin/trash-empty -fv ${toString cfg.trashCleaner.persistance}";
            Type = "oneshot";
          };
        };
      };
    };

    programs = {
      fzf = {
        enable = true;
        enableZshIntegration = cfg.enableZshIntegration;

        colors = mkIf (cfg.fzf.colorscheme != {}) {
          "fg" = "#${cfg.fzf.colorscheme.fg}";
          "fg+" = "#${cfg.fzf.colorscheme.white}";
          "bg" = "#${cfg.fzf.colorscheme.bg}";
          "bg+" = "#${cfg.fzf.colorscheme.black}";
          "hl" = "#${cfg.fzf.colorscheme.blue}";
          "hl+" = "#${cfg.fzf.colorscheme.bright.blue}";
          "info" = "#${cfg.fzf.colorscheme.bright.white}";
          "marker" = "#${cfg.fzf.colorscheme.green}";
          "prompt" = "#${cfg.fzf.colorscheme.red}";
          "spinner" = "#${cfg.fzf.colorscheme.purple}";
          "pointer" = "#${cfg.fzf.colorscheme.purple}";
          "header" = "#${cfg.fzf.colorscheme.blue}";
        };
      };

      tealdeer = {
        enable = true;
        settings = {
          auto_update = cfg.tealdeer.autoUpdate;
          auto_update_interval_hours = 24;
        };
      };

      bat = {
        enable = true;
        config.theme = cfg.bat.theme;
      };
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

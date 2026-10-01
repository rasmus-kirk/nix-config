{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kirk.zsh;
  todoPath =
    if cfg.stateDir != null
    then "${cfg.stateDir}/todo.md"
    else "~/.local/share/todo.md";
  pinnedAt = inputs.nixpkgs.lastModified;
  maxAge = toString cfg.maxNixpkgsAge;
  staleAt = pinnedAt + cfg.maxNixpkgsAge * 24 * 60 * 60;
  warning = ''\033[1;37m[\033[1;33mWARNING\033[1;37m]:\033[0m'';
in {
  options.kirk.zsh = {
    enable = mkEnableOption "zsh configuration.";
    stateDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Where to store stateful ZSH information, ie. the history.";
    };
    maxNixpkgsAge = mkOption {
      type = types.int;
      default = 7;
      description = "Warn in new shells when the pinned nixpkgs is older than this many days.";
    };
    tokenDir = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/data/.secret/tokens-read-only";
      description = "Directory of read-only tokens. Each file is exported as an env var named after the file.";
    };
  };

  config = mkIf cfg.enable {
    programs.nix-index.enable = true;

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh.enable = true;
      envExtra = mkIf (cfg.tokenDir != null) ''
        for token in ${cfg.tokenDir}/*(N); do
          [ -f "$token" ] || continue
          export "$(basename "$token")=$(< "$token")"
        done
      '';
      history = mkIf (cfg.stateDir != null) {
        path = "${cfg.stateDir}/zsh/history";
      };

      sessionVariables = {
        NIXPKGS_ALLOW_UNFREE = "1";
        TERMINAL = "foot";
        # Fix nix path, see: https://github.com/nix-community/home-manager/issues/2564#issuecomment-994943471
        NIX_PATH = "\${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels";
      };

      shellAliases = {
        todo = "$EDITOR ${todoPath}";
        g = "git";
        gs = "git status"; # Fuck ghostscript!
        t = "$TERMINAL </dev/null &>/dev/null zsh &";
      };

      initContent = ''
        if [ "$(date +%s)" -gt ${toString staleAt} ]; then
          echo -e "${warning} nixpkgs is from $(date -d @${toString pinnedAt} +%F), which is older than ${maxAge} days, please run upgrade"
        fi
        gc() {
          git clone --recursive $(wl-paste)
        }
        ns() {
          nix shell --impure nixpkgs#"$1" "''${@:2}"
        }
        nr() {
          nix run --impure nixpkgs#"$1" "''${@:2}"
        }
      '';

      plugins = [
        {
          name = "gruvbox-powerline";
          file = "gruvbox.zsh-theme";
          src = ./gruvbox-powerline;
        }
        {
          name = "zsh-completions";
          src = pkgs.fetchFromGitHub {
            owner = "zsh-users";
            repo = "zsh-completions";
            rev = "0.34.0";
            sha256 = "1c2xx9bkkvyy0c6aq9vv3fjw7snlm0m5bjygfk5391qgjpvchd29";
          };
        }
      ];
    };
  };
}

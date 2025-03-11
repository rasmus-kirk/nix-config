{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.zsh;
in {
  options.kirk.zsh = {
    enable = mkEnableOption "zsh configuration.";
  };

  config = mkIf cfg.enable {
    programs.nix-index.enable = true;

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh.enable = true;

      profileExtra = ''
        # Enable gnome discovery of nix installed programs
        export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

        # Fix nix path, see: https://github.com/nix-community/home-manager/issues/2564#issuecomment-994943471
        export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
      '';

      initExtra = ''
        #alias ls="exa --icons"

        alias rustfmt="cargo +nightly-2023-04-01-x86_64-unknown-linux-gnu fmt"
        alias todo="$EDITOR ~/.local/share/todo.md"
        alias g="git"
        # Fuck ghostscript!
        alias gs="git status"

        # TODO: this is bad, generalize...
        alias t="foot </dev/null &>/dev/null zsh &"

        gc() {
        	git clone --recursive $(wl-paste)
        }

        # What is this?
        if [[ $1 == eval ]]
        then
        	"$@"
        set --
        fi
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

{ config, pkgs, lib, ... }:

with lib;

let
	cfg = config.kirk.zsh;
in {
	options.kirk.zsh= {
		enable = mkEnableOption "kakoune text editor";
	};

	config = mkIf cfg.enable {
		programs.zsh = {
			enable = true;
			enableAutosuggestions = true;
			enableSyntaxHighlighting = true;
			oh-my-zsh.enable = true;

			profileExtra = ''
				# Enable gnome discovery of nix installed programs
				export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

				# Fix nix path, see: https://github.com/nix-community/home-manager/issues/2564#issuecomment-994943471
				export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
			'';

			initExtra = ''
				#alias ls="exa --icons"

				alias nix-shell="nix-shell --run 'zsh'"
				alias rustfmt="cargo +nightly fmt"
				alias todo="$EDITOR ~/.local/share/todo.md"
				alias g="git"
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
					src = pkgs.fetchFromGitHub {
						owner = "rasmus-kirk";
						repo = "gruvbox-powerline";
						rev = "bf5d9422acadfa7b4e834e7117bc8dbc1947004e";
						sha256 = "sha256-bEVR0bKcUBLM8QdyyIWnmnxNl9aCusS8BS6D/qbnIig=";
					};
				} {
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

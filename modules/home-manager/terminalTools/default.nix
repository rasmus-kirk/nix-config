{ config, lib, ... }:

with lib;

let
	cfg = config.kirk.terminalTools;

	tealdeer-config = {
		updates = {
			auto_update = false;
			auto_update_interval_hours = 168;
		};
	};
in {
	options.kirk.terminalTools = {
		enable = mkEnableOption "Quality of life terminal tools";

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
	};

	config = mkIf cfg.enable {
		programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
			# bat
			export MANPAGER="sh -c 'col -bx | bat -l man -p'"
			alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
			alias bathelp='bat --plain --language=help'
			help() {
				"$@" --help 2>&1 | bathelp
			}

			# exa
			alias ll="exa --icons --long"
			alias lh="exa --icons --long --all"
		'';

		# Generate tealdeer config
		xdg.configFile."tealdeer/config.toml" = mkIf cfg.autoUpdateTealdeer {
			source = tomlFormat.generate "tealdeer-config" tealdeer-config;
		};

		programs.bat = {
			enable = true;
			config = {
				theme = cfg.theme;
			};
		};

		home.packages = with pkgs; [
			btop
			silver-searcher
			jq
			tealdeer
			exa
			fd
			duf
			du-dust
		];
	};
}

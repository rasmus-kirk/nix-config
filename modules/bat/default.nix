{ config, lib, ... }:

with lib;

let
	cfg = config.kirk.bat;
in {
	options.kirk.bat = {
		enable = mkEnableOption "foot terminal emulator";

		theme = mkOption {
			type = types.str;
			default = "gruvbox-dark";
			description = "What syntax highlighting colorscheme to use.";
		};

		enableZshIntegration = mkOption {
			type = types.bool;
			default = true;
			description = "Whether to enable zsh integration.";
		};
	};

	config = mkIf cfg.enable {
		programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
			export MANPAGER="sh -c 'col -bx | bat -l man -p'"
			alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
			alias bathelp='bat --plain --language=help'
			help() {
				"$@" --help 2>&1 | bathelp
			}
		'';

		programs.bat = {
			enable = true;
			config = {
				theme = cfg.theme;
			};
		};
	};
}

{ config, pkgs, lib, ... }:

with lib;

let
	cfg = config.kirk.helix;
	mostLsps = with pkgs; [
		# JSON, HTML, CSS, SCSS
		nodePackages_latest.vscode-langservers-extracted
		# Bash
		nodePackages_latest.bash-language-server
		# Docker files
		nodePackages_latest.dockerfile-language-server-nodejs
		# Typescript
		nodePackages_latest.typescript-language-server
		# Python
		python311Packages.python-lsp-server
		# Nix
		nil
		# Rust
		rust-analyzer-unwrapped
		# Makdown
		marksman
		# Latex
		texlab
		# Haskell
		haskell-language-server
		# Go
		gopls
		# Debugger: Rust/CPP/C/Zig
		lldb
	];
in {
	options.kirk.helix = {
		enable = mkEnableOption "helix text editor";

		extraPackages = mkOption {
			type = types.listOf types.package;
			default = [];
			description = "Extra packages to install, for example LSP's.";
		};

		installMostLsps = mkOption {
			type = types.bool;
			default = true;
			description = "Whether or not to install most of the LSP's that helix supports.";
		};
	};

	config = mkIf cfg.enable {
		# Install specified packages
		home.packages = mkMerge [
			cfg.extraPackages 
			(mkIf cfg.installMostLsps mostLsps)
		];

		programs.helix = {
			enable = true;

			settings = {
				theme = "gruvbox";

				editor = {
					mouse = true;
					auto-format = false;
					line-number = "relative";
					shell = ["zsh" "-c"];
					bufferline = "always";

					lsp = {
						display-messages = true;
						display-inlay-hints = true;
					};

					cursor-shape = {
						insert = "bar";
						normal = "block";
					};

					file-picker = {
						hidden = false;
					};

					whitespace = {
						render = {
							space = "none";
							nbsp = "all";
							tab = "all";
							newline = "all";
						};
						characters = {
							newline = "⌄";
						};
					};
				};

				# Make Helix more like kakoune
				keys.normal = {
					# TODO: make this depend on the helix max-width
					#"," = "shell_pipe fmt -w 80";
			
					W = "extend_next_word_end";
					B = "extend_prev_word_start";
					L = "extend_char_right";
					H = "extend_char_left";
					J = "extend_line_down";
					K = "extend_line_up";
					N = "extend_search_next";
					"A-n" = "search_prev";
					"A-N" = "extend_search_prev";
					X = "extend_line_above";

					"A-o" = "add_newline_below";
					"A-O" = "add_newline_above";

					G = {
						l = "extend_to_line_end";
						h = "extend_to_line_start";
					};

					"A-l" = "goto_next_buffer";
					"A-h" = "goto_previous_buffer";

					"C-h" = "jump_backward";
					"C-k" = "half_page_up";
					"C-j" = "half_page_down";
					"C-l" = "jump_forward";

					g = {
						k = "goto_file_start";
						j = "goto_file_end";
						i = "goto_first_nonwhitespace";
					};
				};
			};
		};
	};
}

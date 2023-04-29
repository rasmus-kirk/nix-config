# My home manager config
{ pkgs, config, ... }:
let
	mail = "mail@rasmuskirk.com";
	secretDir = "${config.home.homeDirectory}/.secret";

	# Gruvbox theme colors
	colorscheme = {
		bg = "282828";
		fg = "ebdbb2";

		black  = "1d2021";
		white  = "d5c4a1";
		orange = "d65d0e";
		red    = "cc241d";
		green  = "98971a";
		yellow = "d79921";
		blue   = "458588";
		purple = "b16286";
		teal   = "689d6a";

		bright = {
			black  = "928374";
			white  = "fbf1c7";
			orange = "fe8019";
			red    = "fb4934";
			green  = "b8bb26";
			yellow = "fabd2f";
			blue   = "83a598";
			purple = "d3869b";
			teal   = "8ec07c";
		};
	};

	word-of-the-day = pkgs.writeShellScript "word-of-the-day" ''
		path=${config.xdg.stateHome}/word-of-the-day
		mkdir -p $path
		echo ${pkgs.jiten}/bin/jiten
		if ! [ "$(cat $path/last-update.txt)" = "$(date +"%Y-%m-%d")" ]; then
			${pkgs.jiten}/bin/jiten --colour -v jmdict --romaji -n 1 +random | tail -n +3 > $path/japanese.txt
			echo "" >> $path/japanese.txt
			date +"%Y-%m-%d" > $path/last-update.txt
		fi
	'';

	hm-clean = pkgs.writeShellScriptBin "hm-clean" ''
		# Old command: nix-env --delete-generations 30d

		# Delete old home-manager profiles
		home-manager expire-generations '-30 days'
		# Delete old nix profiles
		nix profile wipe-history --older-than 30d
		# Optimize space
		nix store gc
		nix store optimise
	'';

	hm-update = pkgs.writeShellScriptBin "hm-update" ''
		nix-channel --update
	'';

	hm-upgrade = pkgs.writeShellScriptBin "hm-upgrade" ''
		# Update tldr DB
		${pkgs.tealdeer}/bin/tldr --update
		# Update, switch to new config, and cleanup
		${hm-update}/bin/hm-update
		${hm-rebuild}/bin/hm-rebuild
		${hm-clean}/bin/hm-clean
	'';

	hm-rebuild = pkgs.writeShellScriptBin "hm-rebuild" ''
		home-manager -I home-manager=$HOME/desktop/personal/home-manager switch
	'';
in {
	home.username = "user";
	home.homeDirectory = "/home/user";

	home.stateVersion = "22.11";

	# Let Home Manager install and manage itself.
	programs.home-manager.enable = true;
	
	nixpkgs.config.allowUnfree = true;
	
	targets.genericLinux.enable = true;
	programs.bash = {
		enable = true;
		# Fix programs not showing up
		# Allow home manager to be run
		profileExtra = ''
			export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
		'';
	};

	# Allows installed fonts to be discoverable by OS
	fonts.fontconfig.enable = true;

	# Set fonts
	xdg.configFile = {
		"fontconfig/fonts.conf".text = ''
			<alias>
				<family>monospace</family>
				<prefer>
					<family>FiraCode Nerd Font</family>
					<family>Inconsolata</family>
					<family>DejaVu Sans Mono</family>
				</prefer>
			</alias>
		'';
	};

	xdg.userDirs = {
		enable = true;
		createDirectories = true;

		desktop = "${config.home.homeDirectory}/desktop";
		publicShare = "${config.home.homeDirectory}/public";
		templates = "${config.home.homeDirectory}/templates";
		documents = "${config.home.homeDirectory}/documents";
		download = "${config.home.homeDirectory}/downloads/unsorted";
		music = "${config.home.homeDirectory}/music";
		pictures = "${config.home.homeDirectory}/pictures";
		videos = "${config.home.homeDirectory}/videos";
	};

	programs.ssh = {
		enable = true;
		extraConfig = ''
			IdentityFile ${secretDir}/ssh.key
		'';
	};

	nix = {
		package = pkgs.nix;
		settings = {
			experimental-features = [ "nix-command" "flakes" ];
		};
	};

	systemd.user = {
		timers = {
			word-of-the-day = {
				Unit.Description = "Gets a japanese word from the Jiten dictionary";

				Timer = {
					OnCalendar="daily";
					Persistent="true";
					RandomizedDelaySec="1h";
				};

				Install.WantedBy=["timers.target"];
			};
		};

		services = {
			word-of-the-day = {
				Unit.Description = "Updates the daily japanese word";

				Service = {
					ExecStart = "${word-of-the-day}";
					Type = "oneshot";
				};
			};
		};
	};

	programs.zsh = {
		enable = true;
		enableAutosuggestions = true;
		enableSyntaxHighlighting = true;
		oh-my-zsh = {
			enable = true;
		};

		profileExtra = ''
			export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
			export PATH=$PATH:~/.cargo/bin:~/.local/bin
			export LD_LIBRARY_PATH="${pkgs.zlib}/lib:$LD_LIBRARY_PATH";
		'';

		initExtra = ''
			cat ~/.local/state/word-of-the-day/japanese.txt
		
			function j() {
				ID="$$"
				mkdir -p /tmp/$USER
				OUTPUT_FILE="/tmp/$USER/joshuto-cwd-$ID"
				env joshuto --output-file "$OUTPUT_FILE" $@
				exit_code=$?

				case "$exit_code" in
					# regular exit
					0)
						;;
					# output contains current directory
					101)
						JOSHUTO_CWD=$(cat "$OUTPUT_FILE")
						cd "$JOSHUTO_CWD"
						;;
					# output selected files
					102)
						;;
					*)
						echo "Exit code: $exit_code"
						;;
				esac
			}

			export EDITOR=hx
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels

			# Use bat
			export MANPAGER="sh -c 'col -bx | bat -l man -p'"
			alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
			alias cat="bat"
			alias htop="btop"
			alias bathelp='bat --plain --language=help'
			help() {
				"$@" --help 2>&1 | bathelp
			}

			alias nix-shell="nix-shell --run 'zsh'"
			alias rustfmt="cargo +nightly fmt"
			alias diff="git diff --no-index"
			alias ls="exa --icons"
			alias f="foot </dev/null &>/dev/null zsh &"
			alias g="git"
			alias todo="$EDITOR ~/.local/share/todo.md"
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

	programs.foot = {
		enable = true;
		settings = {
			main = {
				term = "xterm-256color";
				font = "monospace:pixelsize=15";
			};
			colors = {
				alpha = 0.85;
				background = colorscheme.bg;
				foreground = colorscheme.fg;
				regular0 = colorscheme.black;
				regular1 = colorscheme.red;
				regular2 = colorscheme.green;
				regular3 = colorscheme.yellow;
				regular4 = colorscheme.blue;
				regular5 = colorscheme.purple;
				regular6 = colorscheme.teal;
				regular7 = colorscheme.white;
				bright0 = colorscheme.bright.black;
				bright1 = colorscheme.bright.red;
				bright2 = colorscheme.bright.green;
				bright3 = colorscheme.bright.yellow;
				bright4 = colorscheme.bright.blue;
				bright5 = colorscheme.bright.purple;
				bright6 = colorscheme.bright.teal;
				bright7 = colorscheme.bright.white;
			};
			key-bindings = {
				"scrollback-up-half-page" = "Mod1+Shift+K";
				"scrollback-up-line" = "Mod1+K";
				"scrollback-down-half-page" = "Mod1+Shift+J";
				"scrollback-down-line" = "Mod1+J";
				"clipboard-copy" = "Mod1+C Control+Shift+C";
				"clipboard-paste" = "Mod1+V Control+Shift+V";
				"font-increase" = "Mod1+plus Mod1+equal Control+KP_Add";
				"font-decrease" = "Mod1+minus Control+KP_Subtract";
			};
		};
	};

	programs.kakoune = {
		enable = true;
		config = {
			colorScheme = "gruvbox-dark";
			indentWidth = 0;
			tabStop = 2;
			ui.enableMouse = true;
			wrapLines = {
				enable = true;
				word = true;
				marker = "₪";
			};
			numberLines = {
				enable = true;
				highlightCursor = true;
				relative = true;
			};
		};
		extraConfig = ''
			# Highlight whitespace
			add-highlighter global/ show-whitespaces -spc \  -lf ⌄
			
			# Line wrapping
			set global autowrap_column 73
			map global user w '|fmt -w $kak_opt_autowrap_column<ret>' -docstring "Wrap to $kak_opt_autowrap_column columns"
			add-highlighter global/ column '%sh{echo $(($kak_opt_autowrap_column + 1))}' default,black

			# User mappings
			map -docstring "Yank the selection into the clipboard." global user y "<a-|> wl-copy <ret>"
			map -docstring "Paste the clipboard (append)." global user p "<a-!> wl-paste<ret>"
			map -docstring "Paste the clipboard (insert)." global user P "<!> wl-paste<ret>"
			map -docstring "Replace with the clipboard (insert)." global user R "d<!> wl-paste<ret>"
			map -docstring "Replace all space indents with tabs." global user @ "s^ +<ret><a-@>;xs\t\t<ret>;d"
			
			# Differentiate insert and normal mode using colors
			set-face global PrimarySelection white,blue+F
			set-face global SecondarySelection black,blue+F
			set-face global PrimaryCursor black,bright-cyan+F
			set-face global SecondaryCursor black,bright-blue+F
			set-face global PrimaryCursorEol black,bright-cyan
			set-face global SecondaryCursorEol black,bright-blue
			
			hook global ModeChange ".*:insert" %{
				set-face window PrimarySelection white,green+F
				set-face window SecondarySelection black,green+F
				set-face window PrimaryCursor black,bright-yellow+F
				set-face window SecondaryCursor black,bright-green+F
				set-face window PrimaryCursorEol black,bright-yellow
				set-face window SecondaryCursorEol black,bright-green
			}
			
			hook global ModeChange ".*:normal" %{
				unset-face window PrimarySelection
				unset-face window SecondarySelection
				unset-face window PrimaryCursor
				unset-face window SecondaryCursor
				unset-face window PrimaryCursorEol
				unset-face window SecondaryCursorEol
			}
		'';
	};

	programs.zathura = {
		enable = true;
		options = {
			selection-clipboard = "clipboard";
			default-bg = "#${colorscheme.bg} #00";
			default-fg = "#${colorscheme.fg} #01";
			statusbar-fg = "#${colorscheme.fg} #04";
			statusbar-bg = "#${colorscheme.black} #01";
			inputbar-bg = "#${colorscheme.bg} #00";
			inputbar-fg = "#${colorscheme.white} #02";
			notification-bg = "#${colorscheme.fg} #08";
			notification-fg = "#${colorscheme.bg} #00";
			notification-error-bg = "#${colorscheme.red} #08";
			notification-error-fg = "#${colorscheme.fg} #00";
			notification-warning-bg = "#${colorscheme.yellow} #08";
			notification-warning-fg = "#${colorscheme.fg} #00";
			highlight-color = "#${colorscheme.bright.yellow} #0A";
			highlight-active-color = "#${colorscheme.bright.green} #0D";
			recolor-lightcolor = "#${colorscheme.bg}";
			recolor-darkcolor = "#${colorscheme.fg}";
			recolor-reverse-video = "true";
			recolor-keephue = "true";
		};
		mappings = {
			f = "toggle_fullscreen";
			r = "reload";
			R = "rotate";
			H = "navigate previous";
			K = "zoom out";
			J = "zoom in";
			L = "navigate next";
			i = "recolor";
			"<Right>" = "navigate next";
			"<Left>" = "navigate previous";
			"[fullscreen] f" = "toggle_fullscreen";
			"[fullscreen] r" = "reload";
			"[fullscreen] R" = "rotate";
			"[fullscreen] H" = "navigate -1";
			"[fullscreen] K" = "zoom out";
			"[fullscreen] J" = "zoom in";
			"[fullscreen] L" = "navigate 1";
			"[fullscreen] i" = "recolor";
			"[fullscreen] <Right>" = "navigate next";
			"[fullscreen] <Left>" = "navigate previous";
		};
	};

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

	programs.git = {
		enable = true;
		userEmail = mail;
		userName = "rasmus-kirk";
		delta = {
			enable = true;
			options = {
				features = "gruvmax-fang"; 
			};
		};
		includes = [
			# Delta plugins
			{
				path = pkgs.fetchFromGitHub {
				owner = "dandavison";
					repo = "delta";
					rev = "85e2f8e490498629a806af01b960e0510bff3973";
					sha256 = "sha256-vEv3HdLeI3ZXBCSmvd0x7DgEu+DiQqEwFf+WLDdL+4U=";
				} + "/themes.gitconfig";
			}
		];
		aliases = {
			update = "submodule update --init --recursive";
			unstage = "restore --staged";
			d = "diff";
			dc = "diff --cached";
			c = "commit";
			a = "add .";
			ca = "commit -a";
			s = "status";
			su = "status -uno";
			co = "checkout --recurse-submodules";
			l = "log";
		};
		extraConfig = {
			push = {
				autoSetupRemote = true;
			};
			pull = {
				rebase = true;
			};
		};
	};

	programs.fzf = {
		enable = true;
		enableZshIntegration = true;
		colors = {
			"fg" = "#${colorscheme.fg}";
			"fg+" = "#${colorscheme.white}";
			"bg" = "#${colorscheme.bg}";
			"bg+" = "#${colorscheme.black}";
			"hl" = "#${colorscheme.blue}";
			"hl+" = "#${colorscheme.bright.blue}";
			"info" = "#${colorscheme.bright.white}";
			"marker" = "#${colorscheme.green}";
			"prompt" = "#${colorscheme.red}";
			"spinner" = "#${colorscheme.purple}";
			"pointer" = "#${colorscheme.purple}";
			"header" = "#${colorscheme.blue}";
		};
	};

	programs.bat = {
		enable = true;
		config = {
			theme = "gruvbox-dark";
		};
	};

	programs.joshuto = {
		enable = true;

		settings = {
			display = {
				automatically_count_lines = true;
				show_icons = true;
			};
		};

		keymap = {
			default_view.keymap = [
				#{ keys = [ "escape" ]; command = "escape"; }
				{ keys = [ "q" ]; command = "quit --output-current-directory"; }
				{ keys = [ "Q" ]; command = "close_tab"; }

				{ keys = [ "R" ]; command = "reload_dirlist"; }
				{ keys = [ "." ]; command = "toggle_hidden"; }
				{ keys = [ "e" ]; command = "shell hx %s"; }

				{ keys = [ "1" ]; command = "tab_switch_index 1"; }
				{ keys = [ "2" ]; command = "tab_switch_index 2"; }
				{ keys = [ "3" ]; command = "tab_switch_index 3"; }
				{ keys = [ "4" ]; command = "tab_switch_index 4"; }
				{ keys = [ "5" ]; command = "tab_switch_index 5"; }

				# arrow keys
				{ keys = [ "arrow_up" ]; command = "cursor_move_up"; }
				{ keys = [ "arrow_down" ]; command = "cursor_move_down"; }
				{ keys = [ "arrow_left" ]; command = "cd .."; }
				{ keys = [ "arrow_right" ]; command = "open"; }
				{ keys = [ "\n" ]; command = "open"; }
				{ keys = [ "home" ]; command = "cursor_move_home"; }
				{ keys = [ "end" ]; command = "cursor_move_end"; }
				{ keys = [ "page_up" ]; command = "cursor_move_page_up"; }
				{ keys = [ "page_down" ]; command = "cursor_move_page_down"; }
				{ keys = [ "ctrl+u" ];   command = "cursor_move_page_up 0.5"; }
				{ keys = [ "ctrl+d" ]; command = "cursor_move_page_down 0.5"; }

				# vim-like keybindings
				{ keys = [ "j" ]; command = "cursor_move_down"; }
				{ keys = [ "k" ]; command = "cursor_move_up"; }
				{ keys = [ "h" ]; command = "cd .."; }
				{ keys = [ "l" ]; command = "open"; }
				{ keys = [ "g" "g" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "k" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "j" ]; command = "cursor_move_end"; }
				{ keys = [ "g" "e" ]; command = "cursor_move_end"; }

				{ keys = [ "K" ]; command = "parent_cursor_move_up"; }
				{ keys = [ "J" ]; command = "parent_cursor_move_down"; }

				{ keys = [ "c" "d" ]; command = ":cd "; }
				{ keys = [ "d" "d" ]; command = "cut_files"; }
				{ keys = [ "y" "y" ]; command = "copy_files"; }
				{ keys = [ "y" "n" ]; command = "copy_filename"; }
				{ keys = [ "y" "." ]; command = "copy_filename_without_extension"; }
				{ keys = [ "y" "p" ]; command = "copy_filepath"; }
				{ keys = [ "y" "d" ]; command = "copy_dirpath"; }

				{ keys = [ "d" "D" ]; command = "delete_files --foreground=true"; }

				{ keys = [ "p" "p" ]; command = "paste_files"; }
				{ keys = [ "p" "o" ]; command = "paste_files --overwrite=true"; }

				{ keys = [ "a" ]; command = "rename_append"; }
				{ keys = [ "A" ]; command = "rename_prepend"; }

				{ keys = [ " " ]; command = "select --toggle=true"; }
				{ keys = [ "%" ]; command = "select --all=true --toggle=true"; }

				{ keys = [ "t" ]; command = "show_tasks --exit-key=t"; }
				{ keys = [ "b" "b" ]; command = "bulk_rename"; }
				{ keys = [ "=" ]; command = "set_mode"; }

				{ keys = [ ":" ]; command = ":"; }
				{ keys = [ ";" ]; command = ":"; }

				{ keys = [ "'" ]; command = ":shell "; }
				{ keys = [ "m" "d" ]; command = ":mkdir "; }
				{ keys = [ "m" "j" ]; command = "shell sh -c 'foot zsh -is eval j > /dev/null 2>&1 &'"; }
				{ keys = [ "m" "t" ]; command = "shell sh -c 'foot zsh > /dev/null 2>&1 &'"; }

				{ keys = [ "m" "f" ]; command = ":touch "; }

				{ keys = [ "r" ]; command = "bulk_rename"; }
				{ keys = [ "ctrl+r" ]; command = ":rename "; }

				{ keys = [ "/" ]; command = ":search_inc "; }
				{ keys = [ "|" ]; command = "search_fzf"; }
				{ keys = [ "\\" ]; command = "subdir_fzf"; }

				{ keys = [ "n" ]; command = "search_next"; }
				{ keys = [ "alt+n" ]; command = "search_prev"; }

				{ keys = [ "s" "r" ]; command = "sort reverse"; }
				{ keys = [ "s" "l" ]; command = "sort lexical"; }
				{ keys = [ "s" "m" ]; command = "sort mtime"; }
				{ keys = [ "s" "n" ]; command = "sort natural"; }
				{ keys = [ "s" "s" ]; command = "sort size"; }
				{ keys = [ "s" "e" ]; command = "sort ext"; }

				{ keys = [ "~" ]; command = "cd ~/"; }
				{ keys = [ "`" ]; command = "cd /"; }
				{ keys = [ "?" ]; command = "help"; }
			];

			task_view.keymap = [
				# arrow keys
				{ keys = [ "arrow_up" ]; command = "cursor_move_up"; }
				{ keys = [ "arrow_down" ]; command = "cursor_move_down"; }
				{ keys = [ "home" ]; command = "cursor_move_home"; }
				{ keys = [ "end" ]; command = "cursor_move_end"; }

				# vim-like keybindings
				{ keys = [ "j" ]; command = "cursor_move_down"; }
				{ keys = [ "k" ]; command = "cursor_move_up"; }
				{ keys = [ "g" "g" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "k" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "j" ]; command = "cursor_move_end"; }
				{ keys = [ "g" "e" ]; command = "cursor_move_end"; }

				{ keys = [ "w" ]; command = "show_tasks"; }
				{ keys = [ "escape" ]; command = "show_tasks"; }
				{ keys = [ "q" ]; command = "show_tasks"; }
			];

			help_view.keymap = [
				# arrow keys
				{ keys = [ "arrow_up" ]; command = "cursor_move_up"; }
				{ keys = [ "arrow_down" ]; command = "cursor_move_down"; }
				{ keys = [ "home" ]; command = "cursor_move_home"; }
				{ keys = [ "end" ]; command = "cursor_move_end"; }

				# vim-like keybindings
				{ keys = [ "j" ]; command = "cursor_move_down"; }
				{ keys = [ "k" ]; command = "cursor_move_up"; }
				{ keys = [ "g" "g" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "k" ]; command = "cursor_move_home"; }
				{ keys = [ "g" "j" ]; command = "cursor_move_end"; }
				{ keys = [ "g" "e" ]; command = "cursor_move_end"; }

				{ keys = [ "w" ]; command = "show_tasks"; }
				{ keys = [ "escape" ]; command = "show_tasks"; }
				{ keys = [ "q" ]; command = "show_tasks"; }
			];
		};

		mimetype = {
			class = {
				audio_default = [{
					command = "mpv";
					args = [ "--" ];
				} {
					command = "mediainfo";
					confirm_exit = true;
				}];
				video_default = [{
					command = "mpv";
					args = [ "--" ];
				} {
					command = "mediainfo";
					confirm_exit = true;
				}];
				text_default = [
					{ command = "hx"; }
					{ command = "nano"; }
				];
				reader_default = [
					{
						command = "zathura";
						fork = true;
						silent = true;
					}
				];
				libreoffice_default = [
					{
						command = "libreoffice";
						fork = true;
						silent = true;
					}
				];
			};

			extension = {
				# Document
				pdf."inherit"    = "reader_default"; 

				# Images
				avif."inherit"   = "image_default";
				bmp."inherit"    = "image_default";
				gif."inherit"    = "image_default";
				heic."inherit"   = "image_default";
				jpeg."inherit"   = "image_default";
				jpe."inherit"    = "image_default";
				jpg."inherit"    = "image_default";
				pgm."inherit"    = "image_default";
				png."inherit"    = "image_default";
				ppm."inherit"    = "image_default";
				webp."inherit"   = "image_default";

				# Audio
				flac."inherit"   = "audio_default";
				m4a."inherit"    = "audio_default";
				mp3."inherit"    = "audio_default";
				ogg."inherit"    = "audio_default";
				wav."inherit"    = "audio_default";

				# Video
				avi."inherit"    = "video_default";
				av1."inherit"    = "video_default";
				flv."inherit"    = "video_default";
				mkv."inherit"    = "video_default";
				m4v."inherit"    = "video_default";
				mov."inherit"    = "video_default";
				mp4."inherit"    = "video_default";
				ts."inherit"     = "video_default";
				webm."inherit"   = "video_default";
				wmv."inherit"    = "video_default";

				# Text
				build."inherit"  = "text_default";
				c."inherit"      = "text_default";
				cmake."inherit"  = "text_default";
				conf."inherit"   = "text_default";
				cpp."inherit"    = "text_default";
				css."inherit"    = "text_default";
				csv."inherit"    = "text_default";
				cu."inherit"     = "text_default";
				ebuild."inherit" = "text_default";
				eex."inherit"    = "text_default";
				env."inherit"    = "text_default";
				ex."inherit"     = "text_default";
				exs."inherit"    = "text_default";
				go."inherit"     = "text_default";
				h."inherit"      = "text_default";
				hpp."inherit"    = "text_default";
				hs."inherit"     = "text_default";
				html."inherit"   = "text_default";
				ini."inherit"    = "text_default";
				java."inherit"   = "text_default";
				js."inherit"     = "text_default";
				json."inherit"   = "text_default";
				kt."inherit"     = "text_default";
				lua."inherit"    = "text_default";
				log."inherit"    = "text_default";
				md."inherit"     = "text_default";
				micro."inherit"  = "text_default";
				ninja."inherit"  = "text_default";
				nix."inherit"    = "text_default";
				py."inherit"     = "text_default";
				rkt."inherit"    = "text_default";
				rs."inherit"     = "text_default";
				scss."inherit"   = "text_default";
				sh."inherit"     = "text_default";
				srt."inherit"    = "text_default";
				svelte."inherit" = "text_default";
				toml."inherit"   = "text_default";
				tsx."inherit"    = "text_default";
				txt."inherit"    = "text_default";
				vim."inherit"    = "text_default";
				xml."inherit"    = "text_default";
				yaml."inherit"   = "text_default";
				yml."inherit"    = "text_default";
			};

			mimetype = {
				mimetype.text = {
					"inherit" = "text_default";
				};
			};
		};
	};

	home.packages = with pkgs; [
		# Misc
		vscode
		gnome.gnome-tweaks
		keepassxc
		thunderbird

		# LSP's/debuggers
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

		# PL's
		yarn

		# Browsers
		librewolf
		chromium

		# Media
		mpv

		# Chat
		slack
		signal-desktop

		# Fonts
		nerdfonts
		fira-code

		# Document handling
		texlive.combined.scheme-full
		pandoc

		# Misc Terminal Tools
		btop
		wl-clipboard
		trash-cli
		silver-searcher
		jq
		htop
		tealdeer
		bat
		exa
		yt-dlp
		fd
		duf
		du-dust

		# Home Manager scripts
		hm-update
		hm-upgrade
		hm-rebuild
		hm-clean

		# Procex
		#(import ./procex/default.nix args) 
	];
}

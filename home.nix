# My home manager config

{ config, pkgs, ... }:
let
	mail = "mail@rasmuskirk.com";
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

	programs.zsh = {
		enable = true;
		enableAutosuggestions = true;
		enableSyntaxHighlighting = true;
		oh-my-zsh = {
			enable = true;
			# custom = "${./zsh/custom}";
			# theme = "gruvbox";
		};

		profileExtra = ''
			export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
			export PATH=$PATH:~/.cargo/bin
		'';

		initExtra = ''
			lfcd () {
				tmp="$(mktemp)"
				# `command` is needed in case `lfcd` is aliased to `lf`
				command lf -last-dir-path="$tmp" "$@"
				if [ -f "$tmp" ]; then
					dir="$(cat "$tmp")"
					rm -f "$tmp"
					if [ -d "$dir" ]; then
						if [ "$dir" != "$(pwd)" ]; then
							cd "$dir"
						fi
					fi
				fi
			}
			alias n="lfcd"

			export EDITOR=kak
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
		'';

		plugins = [
			{
				name = "gitit";
				src = pkgs.fetchFromGitHub {
					owner = "peterhurford";
					repo = "git-it-on.zsh";
					rev = "4827030e1ead6124e3e7c575c0dd375a9c6081a2";
					sha256 = "01xsqhygbxmv38vwfzvs7b16iq130d2r917a5dnx8l4aijx282j2";
				};
			} {
				name = "powerlevel9k";
				file = "powerlevel9k.zsh-theme";
				src = pkgs.fetchFromGitHub {
					owner = "bhilburn";
					repo = "powerlevel9k";
					rev = "571a859413866897cf962396f02f65a288f677ac";
					sha256 = "0xwa1v3c4p3cbr9bm7cnsjqvddvmicy9p16jp0jnjdivr6y9s8ax";
				};
			} {
				name = "zsh-completions";
				src = pkgs.fetchFromGitHub {
					owner = "zsh-users";
					repo = "zsh-completions";
					rev = "0.27.0";
					sha256 = "1c2xx9bkkvyy0c6aq9vv3fjw7snlm0m5bjygfk5391qgjpvchd29";
				};
			} {
				name = "nix-shell";
				src = pkgs.fetchFromGitHub {
					owner = "chisui";
					repo = "zsh-nix-shell";
					rev = "03a1487655c96a17c00e8c81efdd8555829715f8";
					sha256 = "1avnmkjh0zh6wmm87njprna1zy4fb7cpzcp8q7y03nw3aq22q4ms";
				};
			}
		];
	};

	programs.foot = {
		enable = true;
		settings = {
			main = {
				term = "xterm-256color";
				font = "monospace:pixelsize=16";
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
		};
	};

	programs.git = {
		enable = true;
		userEmail = mail;
		userName = "rasmus-kirk";
		delta.enable = true;
		aliases = {
			update = "submodule update --init --recursive";
			d = "diff";
			dc = "diff --cached";
			c = "clone --recursive $(wl-paste)";
		};
		extraConfig = {
			push = {
				autoSetupRemote = true;
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

	programs.ssh.enable = true;

	# TODO: Create lf module...
	programs.lf = {
		enable = true;
		keybindings = {
			"." = "set hidden!";
			D   = "trash";
			x   = "trash";
			bc  = "cd ~/Desktop/concordium";
		};
	};

	home.packages = with pkgs; [
		vscode
		keepassxc
		slack
		librewolf
		thunderbird
		wl-clipboard
		chromium
		trash-cli
		gnome.gnome-tweaks
		nerdfonts
		fira-code
		mpv
		htop
		signal-desktop
		tldr
	];
}

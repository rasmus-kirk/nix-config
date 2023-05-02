# My home manager config
{ pkgs, config, ... }:
let
	secretDir = "${config.home.homeDirectory}/.secret";

	# Gruvbox theme colors
	# Type: attrs
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
	imports = [ ./modules ];

	kirk = {
		foot = { enable = true; colorscheme = colorscheme; };
		git.enable = true;
		helix.enable = true;
		jiten.enable = true;
		joshuto.enable = true;
		kakoune.enable = true;
	};

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
			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels

			# Use bat
			export MANPAGER="sh -c 'col -bx | bat -l man -p'"
			alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
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

	home.packages = with pkgs; [
		# Misc
		vscode
		gnome.gnome-tweaks
		keepassxc
		thunderbird
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
		wl-clipboard
		trash-cli
		yt-dlp

		btop
		silver-searcher
		jq
		tealdeer
		bat
		exa
		fd
		duf
		du-dust

		# Home Manager scripts
		hm-update
		hm-upgrade
		hm-rebuild
		hm-clean
	];
}

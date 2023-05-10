# My home manager config
{ pkgs, config, ... }:
let
	secretDir = "${config.home.homeDirectory}/.secret";
	configDir = "${config.home.homeDirectory}/.system-configuration";
	username = "user";

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
in {
	kirk = {
		bat.enable = true;
		foot = { enable = true; colorscheme = colorscheme; };
		fzf = { enable = true; colorscheme = colorscheme; };
		git.enable = true;
		helix.enable = true;
		homeManagerScripts = { enable = true; configDir = configDir; };
		jiten.enable = true;
		joshuto.enable = true;
		kakoune.enable = true;
		ssh = { enable = true; identityPath = "${secretDir}/ssh.key"; };
		userDirs = { enable = true; autoSortDownloads = true; };
		zathura = { enable = true; colorscheme = colorscheme; };
		zsh.enable = true;
	};

	home.username = username;
	home.homeDirectory = "/home/${username}";

	home.stateVersion = "22.11";

	# Let Home Manager install and manage itself.
	programs.home-manager.enable = true;
	
	nixpkgs.config.allowUnfree = true;
	
	targets.genericLinux.enable = true;

	nix = {
		package = pkgs.nix;
		settings.experimental-features = [ "nix-command" "flakes" ];
	};

	programs.bash = {
		enable = true;
		profileExtra = ''
			# Fix programs not showing up
			#export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

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

	programs.zsh.profileExtra = ''
		export PATH=$PATH:~/.cargo/bin:~/.local/bin
		# Fix weird cargo concordium bug
		export LD_LIBRARY_PATH="${pkgs.zlib}/lib:$LD_LIBRARY_PATH";
		# Fix nix programs not showing up in gnome menus:
		export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"
	'';

	home.packages = with pkgs; [
		# Misc
		#vscode
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
		(nerdfonts.override { fonts = [ "FiraCode" ]; })
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
		exa
		fd
		duf
		du-dust
	];
}

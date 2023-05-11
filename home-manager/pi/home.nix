# My home manager config
{ pkgs, ... }:
let
	secretDir = "/config/.secret";
	configDir = "/config/.system-configuration";
	machine = "pi";
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
		fzf = { enable = true; colorscheme = colorscheme; };
		git.enable = true;
		helix = { 
			enable = true;
			installMostLsps = false;
			extraPackages = with pkgs; [ nil marksman nodePackages_latest.bash-language-server ];
		};
		homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
		joshuto.enable = true;
		kakoune.enable = true;
		ssh = { enable = true; identityPath = "${secretDir}/ssh/id_rsa"; };
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

	home.packages = with pkgs; [
		# Fonts
		(nerdfonts.override { fonts = [ "FiraCode" ]; })
		fira-code

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

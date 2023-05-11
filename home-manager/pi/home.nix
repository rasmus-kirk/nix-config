# My home manager config
{ colorscheme, pkgs, ... }:
let
	secretDir = "/config/.secret";
	configDir = "/config/.system-configuration";
	machine = "pi";
	username = "user";
in {
	kirk = {
		terminalTools.enable = true;
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
	];
}

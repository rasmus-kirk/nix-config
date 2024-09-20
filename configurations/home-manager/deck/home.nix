# My home manager config
{ pkgs, config, ... }:
let
	username = "user";
	machine = "deck";
	dataDir = "/data";
	configDir = "${dataDir}/.system-configuration";
	secretDir = "${dataDir}/.secret";
in {
	kirk = {
		terminalTools.enable = true;
		foot.enable = true;
		fzf.enable = true;
		git = {
			enable = true;
			userEmail = "mail@rasmuskirk.com";
			userName = "rasmus-kirk";
		};
		helix.enable = true;
		homeManagerScripts = { 
			enable = true; 
			configDir = configDir; 
			machine = machine; 
		};
		jiten.enable = false;
		joshuto.enable = true;
		kakoune.enable = true;
		ssh = { 
			enable = true; 
			identityPath = "${secretDir}/deck/ssh/id_ed25519";
		};
		userDirs = { 
			enable = true; 
			autoSortDownloads = true; 
		};
		zathura.enable = true;
		zsh.enable = true;
		fonts.enable = true;
	};

	home.username = username;
	home.homeDirectory = "/home/${username}";

	home.stateVersion = "22.11";

	# Let Home Manager install and manage itself.
	programs.home-manager.enable = true;
	
	targets.genericLinux.enable = true;

	nix = {
		package = pkgs.nix;
		settings.experimental-features = [ "nix-command" "flakes" ];
	};

	programs.bash = {
		enable = true;
		profileExtra = ''
			# Fix programs not showing up
			export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"
		'';

		initExtra = "exec zsh";
	};

	home.packages = with pkgs; [
		# Misc
		freetube
		jellyfin
		mpv
	
		# Browsers
		librewolf

		# Chat
		signal-desktop

		# Fonts
		(nerdfonts.override { fonts = [ "FiraCode" ]; })
		fira-code

		# Misc Terminal Tools
		wl-clipboard
	];
}

# My home manager config
{ pkgs, config, ... }:
let
	configDir = "${config.home.homeDirectory}/.system-configuration";
	username = "user";
	machine = "emil";
in {
	kirk = {
		terminalTools.enable = true;
		foot.enable = true;
		fzf.enable = true;
		homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
		joshuto.enable = true;
		kakoune.enable = true;
		zsh.enable = true;
		fonts.enable = true;
	};

	home.username = username;
	home.homeDirectory = "/home/${username}";

	home.stateVersion = "22.11";

	# Let Home Manager install and manage itself.
	programs.home-manager.enable = true;
	
	targets.genericLinux.enable = true;

	services.syncthing.enable = true;

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
		stremio
	
		# Browsers
		chrome

		# Chat
		signal-desktop

		# Fonts
		(nerdfonts.override { fonts = [ "FiraCode" ]; })
		fira-code

		# Misc Terminal Tools
		wl-clipboard
		git
	];
}

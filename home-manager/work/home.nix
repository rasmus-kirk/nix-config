# My home manager config
{ pkgs, config, ... }:
let
	secretDir = "${config.home.homeDirectory}/.secret";
	configDir = "${config.home.homeDirectory}/.system-configuration";
	username = "user";
	machine = "work";
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
		homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
		jiten.enable = true;
		joshuto.enable = true;
		kakoune.enable = true;
		ssh = { enable = true; identityPath = "${secretDir}/id_ed25519"; };
		userDirs = { enable = true; autoSortDownloads = true; };
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

			export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
		'';

		initExtra = "exec zsh";
	};

	# TODO: Add to kirk-module
	programs.mpv = {
		enable = true;
		bindings = {
			UP = "add chapter 1";
			DOWN = "add chapter -1";
			ESC = "quit";
			ENTER = "cycle pause";
			f = "cycle fullscreen";
			h = "seek -5";
			j = "add chapter -1";
			k = "add chapter 1";
			l = "seek 5";

			"Shift+LEFT" = "cycle sub down";
			"Shift+RIGHT" = "cycle sub";
			"Shift+UP" = "cycle audio";
			"Shift+DOWN" = "cycle audio down";

			y = "add audio-delay 0.010";
			o = "add audio-delay -0.010";

			i = ''cycle-values vf "sub,lavfi=negate" ""'';
			S = "playlist-shuffle";

			a = "ab-loop";

			"Alt+r" = "playlist-shuffle";
		};
		scripts = with pkgs.mpvScripts; [ 
			# Load all files in directory to playlist, playing next alphabetically ordered file on playback end.
			autoload
			# Better UI
			uosc
			# Allows media playback buttons to work in mpv
			mpris
			# Thumbnail support, needs uosc to work
			thumbfast
			# Prevents screen sleep on gnome
			inhibit-gnome
		];
		config = {
			# TODO: wtf is the reason for this? It should not be necessary. WHY DOES IT WORK!?
			vo = "x11";

			alang = [ "jpn" "eng" ];
			slang = [ "eng" ];
			#extension.gif = {
			#	cache = "no";
			#	no-pause = "";
			#	loop-file = "yes";
			#};
			#extension.webm = {
			#	no-pause = "";
			#	loop-file = "yes";
			#};
		};
	};

	programs.zsh.profileExtra = ''
		export PATH=$PATH:~/.cargo/bin:~/.local/bin

		# Fix weird cargo concordium bug
		export LD_LIBRARY_PATH="${pkgs.zlib}/lib:$LD_LIBRARY_PATH";

		# Fix nix programs not showing up in gnome menus:
		#export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

		export XCURSOR_THEME="Capitaine Cursors (Gruvbox)"
		export XCURSOR_PATH="$XCURSOR_PATH":/usr/share/icons:~/.local/share/icons
	'';

	home.packages = with pkgs; [
		# Misc
		gnome.gnome-tweaks
		keepassxc
		thunderbird
		yarn

		# Browsers
		librewolf
		chromium

		# Media
		qbittorrent
		#mpv

		# Crytpo
		monero-gui

		# Chat
		slack
		signal-desktop

		# Fonts
		(nerdfonts.override { fonts = [ "FiraCode" ]; })
		fira-code

		# Document handling
		texlive.combined.scheme-full
		pandoc
		inotify-tools

		# Misc Terminal Tools
		wl-clipboard
		yt-dlp
	];
}

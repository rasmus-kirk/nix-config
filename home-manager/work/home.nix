# My home manager config
{ colorscheme, pkgs, config, ... }:
let
	secretDir = "${config.home.homeDirectory}/.secret";
	configDir = "${config.home.homeDirectory}/.system-configuration";
	username = "user";
	machine = "work";
in {
	kirk = {
		terminalTools.enable = true;
		foot = { enable = true; colorscheme = colorscheme; };
		fzf = { enable = true; colorscheme = colorscheme; };
		git.enable = true;
		helix.enable = true;
		homeManagerScripts = { enable = true; configDir = configDir; machine = machine; };
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
	];
}

args@{ config, pkgs, ... }:
let
	username = "user";
	secretDir = "/config/.secret";
in {
	age = {
		identityPaths = [ "${secretDir}/ssh/id_rsa" ];
		secrets = {
			wifi.file = "${secretDir}/wifi.age";
			user.file = "${secretDir}/user.age";
			wg-mullvad.file = "${secretDir}/wg-mullvad.age";
			wg-mediaserver.file = "${secretDir}/wg-mediaserver.age";
		};
	};

	# Required for the Wireless firmware
	#hardware.enableRedistributableFirmware = true;

	networking = {
		hostName = "pi"; # Define your hostname.
		wireless = {
			enable = true;
			environmentFile = config.age.secrets.wifi.path;
			networks = {
				"PET-vogn" = { psk = "@ROOM@"; };
			};
		};
	};

	users = {
		mutableUsers = false;
		users."${username}" = {
			shell = pkgs.zsh;
			isNormalUser = true;
			passwordFile = config.age.secrets.user.path;
			extraGroups = [ "wheel" ];
		};
	};

	services.openssh = {
		enable = true;
		openFirewall = true;
		passwordAuthentication = false;
		ports = [6000];
	};
	users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
		"${./pubkeys/laptop.pub}"
		"${./pubkeys/steam-deck.pub}"
	];

	services.getty.autologinUser = username;

	programs.zsh.enable = true;

	nix = {
		settings = {
			auto-optimise-store = true;
		};
		gc = {
			automatic = true;
			dates = "weekly";
			options = "--delete-older-than 30d";
		};
		package = pkgs.nixUnstable;
		extraOptions = ''
			experimental-features = nix-command flakes
			min-free = ${toString (100 * 1024 * 1024)}
			max-free = ${toString (1024 * 1024 * 1024)}
		'';
	};

	# Assuming this is installed on top of the disk image.
	fileSystems = {
		"/" = {
			device = "/dev/disk/by-label/NIXOS_SD";
			fsType = "ext4";
			options = [ "noatime" ];
		};
		#"/data" = {
		#	device = "/dev/disk/by-label/storage-ssd";
		#	fsType = "btrfs";
		#	options = [ "noatime" ];
		#};
	};

	environment.systemPackages = with pkgs; [
		# Compression
		zip
		unar
		unzip
		p7zip
		# Terminal programs
		git
		smartmontools
		fzf
		ffmpeg
		nmap
		trash-cli
		wget
	];

	nixpkgs.config.allowUnfree = true;

	powerManagement.cpuFreqGovernor = "ondemand";

	system.stateVersion = "20.09";
}


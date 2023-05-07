{ config, pkgs, ... }:
let
	username = "user";
in {
	imports = [
		./age.nix
		#(import ./mullvad.nix args)
		#(import ./wireguard.nix args)

		#(import ../../scripts username args)

		(import ../../modules/nixos/openssh username args)

		#(import ../../modules/misc/kakoune   username args)
		#(import ../../modules/server/nnn     username args)
		#(import ../../modules/misc/zsh       username args)

		#(import ../../modules/server/flood     mediaUser stateDir args)
		#(import ../../modules/server/rtorrent  mediaUser stateDir downloadDir args)
		#(import ../../modules/server/jackett   mediaUser stateDir args)
		#(import ../../modules/server/nzbhydra2           stateDir args)
		#(import ../../modules/server/ombi      mediaUser stateDir args)
		#(import ../../modules/server/radarr    mediaUser stateDir downloadDir args)
		#(import ../../modules/server/sabnzbd   mediaUser stateDir downloadDir args)
		#(import ../../modules/server/sonarr    mediaUser stateDir downloadDir args)
		#(import ../../modules/jellyfin  mediaUser stateDir args)
	];

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
			isNormalUser = true;
			passwordFile = config.age.secrets.user.path;
			extraGroups = [ "wheel" ];
		};
	};

	services.getty.autologinUser = username;

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
		"/data" = {
			device = "/dev/disk/by-label/storage-ssd";
			fsType = "btrfs";
			options = [ "noatime" ];
		};
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


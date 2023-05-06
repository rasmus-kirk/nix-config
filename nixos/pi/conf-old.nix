args@{ config, pkgs, lib, ... }:
let
	username = "user";
	mediaUser = "mediaUser";
	stateDir = "/data/.state";
	downloadDir = "/data/downloads";
  interface = "wlan0";
  hostname = "pi";
in {
	imports = [
    #"${fetchTarball "https://github.com/NixOS/nixos-hardware/archive/936e4649098d6a5e0762058cb7687be1b2d90550.tar.gz" }/raspberry-pi/4"
		./age.nix
		(import ./mullvad.nix args)
		(import ./wireguard.nix args)

		(import ../../scripts username args)

		(import ../../modules/server/openssh username args)

		#(import ../../modules/misc/kakoune   username args)
		(import ../../modules/server/nnn     username args)
		(import ../../modules/misc/zsh       username args)

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
			extraGroups = [ "wheel" "rtorrent" ];
		};
		users.test  = {
			isNormalUser = true;
		  password = "1234";
			extraGroups = [ "wheel" "rtorrent" ];
		};

		groups."${mediaUser}" = {};
		users."${mediaUser}" = {
			isSystemUser = true;
			group = "${mediaUser}";
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

  services.nextcloud = {
    enable = true;
    hostName = "nextcloud.rasmuskirk.com";
	  package = pkgs.nextcloud26;
    config = {
		  adminpassFile = "${pkgs.writeText "adminpass" "etUniktPasswordHer"}";
      #adminuser = "root";
    };
  };

	services.nginx = {
	  enable = true;
	  recommendedGzipSettings = true;
	  recommendedOptimisation = true;
	  recommendedProxySettings = true;
	  recommendedTlsSettings = true;

	  virtualHosts = {
	    "nextcloud.rasmuskirk.com" = {
				listen = [ { addr = "127.0.0.1"; port = 55329; } ];
	      #forceSSL = true;
	      #enableACME = true;
	    };
	  };
	};

	#security.acme = {
  #  acceptTerms = true;
  #  # Replace the email here!
  #  email = "mail@rasmuskirk.com";
	#};

  networking.firewall.allowedTCPPorts = [ 55329 ];

	environment.systemPackages = with pkgs; [
		# Compression
		zip
		unar
		unzip
		p7zip
		# Terminal programs
		imagemagick
		git
		smartmontools
		macchanger
		duplicity #Backup
		fzf
		bubblewrap
		ffmpeg
		htop
		nmap
		tldr
		trash-cli
		wget
		youtube-dl
	];

	nixpkgs.config.allowUnfree = true;
	powerManagement.cpuFreqGovernor = "ondemand";
	system.stateVersion = "20.09";
	#swapDevices = [ { device = "/swapfile"; size = 3072; } ];
}


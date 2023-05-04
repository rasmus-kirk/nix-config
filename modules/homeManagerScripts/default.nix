{ config, pkgs, lib, ... }:

with lib;

let
	cfg = config.kirk.homeManagerScripts;

	hm-clean = pkgs.writeShellApplication {
		name = "hm-clean"; 
		text = ''
			# Old command: nix-env --delete-generations 30d

			# Delete old home-manager profiles
			home-manager expire-generations '-30 days' &&
			# Delete old nix profiles
			nix profile wipe-history --older-than 30d &&
			# Optimize space
			nix store gc &&
			nix store optimise
		'';
	};

	hm-update = pkgs.writeShellApplication {
		name = "hm-update"; 
		text = ''
			nix-channel --update
		'';
	};

	hm-upgrade = pkgs.writeShellApplication {
		name = "hm-upgrade"; 
		text = ''
			# Update, switch to new config, and cleanup
			${hm-update}/bin/hm-update &&
			${hm-rebuild}/bin/hm-rebuild &&
			${hm-clean}/bin/hm-clean
			echo "Updating TLDR database"
			${pkgs.tealdeer}/bin/tldr --update
		'';
	};

	hm-rebuild = pkgs.writeShellApplication {
		name = "hm-rebuild"; 
		text = ''
			home-manager -I home-manager="$HOME/desktop/personal/home-manager" switch
		'';
	};
in {
	options.kirk.homeManagerScripts= {
		enable = mkEnableOption "home manager scripts";
	};

	config = mkIf cfg.enable {
		home.packages = [
			hm-update
			hm-upgrade
			hm-rebuild
			hm-clean
		];
	};
}

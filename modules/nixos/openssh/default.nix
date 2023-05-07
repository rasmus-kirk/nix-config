username: { config, pkgs, lib, ... }:
{
	services.openssh.enable = true;
	services.openssh.openFirewall = true;
	services.openssh.passwordAuthentication = false;
	services.openssh.ports = [ 6000 ];
	users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
		"${./pubkeys/laptop.pub}"
		"${./pubkeys/steam-deck.pub}"
	];
}

{ config, pkgs, ... }:
let
	port = 55329;
in {
	networking = {
		firewall.allowedUDPPorts = [ port ];
		wg-quick.interfaces.test = {
			address = [ "10.0.0.1/32" ];
			privateKeyFile = config.age.secrets.wg-mediaserver.path;
			listenPort = port;
			peers = [{
				publicKey = "CD66uEutvxP9EDIsG+EzEw6qszG05/G/RNnOlTDF4H4=";
				allowedIPs = [ "10.0.0.2/32" ];
			} {
				publicKey = "hqHW/oo+J+3j48jg6kKUs7TW+n0Y+3smfusjPkvfqVw=";
				allowedIPs = [ "10.0.0.3/32" ];
			}];
		};
	};
}

{ config, pkgs, ... }:
{
	networking.wg-quick.interfaces.mullvad = {
		privateKeyFile = config.age.secrets.wg-mullvad.path;
		address = [ "10.64.233.173/32" "fc00:bbbb:bbbb:bb01::1:e9ac/128" ];
		#dns = [ "10.64.0.1" ];
		peers = [{
			allowedIPs = ["0.0.0.0/0" "::0/0"];
			publicKey = "m4jnogFbACz7LByjo++8z5+1WV0BuR1T7E1OWA+n8h0=";
			endpoint = "193.138.218.130:51820";
		}];
	};

	environment.shellAliases = {
		mullon  = "sudo systemctl start wg-quick-mullvad.service";
		mulloff = "sudo systemctl stop wg-quick-mullvad.service";
	};
}

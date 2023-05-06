{
	age.identityPaths = [ "/config/.secret/ssh/id_rsa" ];

	age.secrets.wifi.file = "/config/.secret/wifi.age";
	age.secrets.user.file = "/config/.secret/user.age";
	age.secrets.wg-mullvad.file = "/config/.secret/wg-mullvad.age";
	age.secrets.wg-mediaserver.file = "/config/.secret/wg-mediaserver.age";
}

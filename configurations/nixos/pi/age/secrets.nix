let
	key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzC8fb2vPowh4zcDc9rI9upzHNm8dCvQwgCEAHKox9c";
in {
	"airvpn-wg.conf.age".publicKeys = [ key ];
	"domain.age".publicKeys = [ key ];
	"njalla.age".publicKeys = [ key ];
	"njalla-vpn.age".publicKeys = [ key ];
	"user.age".publicKeys = [ key ];
	"wifi.age".publicKeys = [ key ];
}

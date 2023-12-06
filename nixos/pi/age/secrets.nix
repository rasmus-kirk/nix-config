let
	key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzC8fb2vPowh4zcDc9rI9upzHNm8dCvQwgCEAHKox9c";
in {
	"user.age".publicKeys = [ key ];
	"mullvad.age".publicKeys = [ key ];
	"wifi.age".publicKeys = [ key ];
}

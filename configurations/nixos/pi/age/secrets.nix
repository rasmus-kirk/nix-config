let
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzC8fb2vPowh4zcDc9rI9upzHNm8dCvQwgCEAHKox9c";
in {
  "airvpn-wg.age".publicKeys = [key];
  "airvpn-wg-address.age".publicKeys = [key];
  "user.age".publicKeys = [key];
  "mullvad.age".publicKeys = [key];
  "wifi.age".publicKeys = [key];
  "domain.age".publicKeys = [key];
}

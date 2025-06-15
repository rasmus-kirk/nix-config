let
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKdn+qACukjNkc76tkvKf94DuUr3LBqLM/lNhlcXYSm7 mail@rasmuskirk.com";
in {
  "airvpn-wg.conf.age".publicKeys = [key];
  "domain.age".publicKeys = [key];
  "mam.age".publicKeys = [key];
  "mam-vpn.age".publicKeys = [key];
  "njalla.age".publicKeys = [key];
  "user.age".publicKeys = [key];
}

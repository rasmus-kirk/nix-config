let
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDgYSiaoC2so74z6rtbvyFPPJGrY732aC6p8ZWivH+0d mail@rasmuskirk.com";
in {
  # "user.age".publicKeys = [key];
  "hosts.age".publicKeys = [key];
}

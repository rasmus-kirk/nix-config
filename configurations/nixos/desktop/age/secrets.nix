let
  read = name: builtins.replaceStrings ["\n"] [""] (builtins.readFile ../../../../ssh-keys/age/${name}.pub);
  keys = [(read "desktop") (read "yubi")];
in {
  "airvpn-wg.conf.age".publicKeys = keys;
  "domain.age".publicKeys = keys;
  "mam.age".publicKeys = keys;
  "mam-vpn.age".publicKeys = keys;
  "1984.age".publicKeys = keys;
  "user.age".publicKeys = keys;
}

let
  read = name: builtins.replaceStrings ["\n"] [""] (builtins.readFile ../../../../ssh-keys/age/${name}.pub);
  keys = [(read "deck-oled") (read "yubi")];
in {
  "hosts.age".publicKeys = keys;
  "wg.conf.age".publicKeys = keys;
}

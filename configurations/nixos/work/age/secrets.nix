let
  read = name: builtins.replaceStrings ["\n"] [""] (builtins.readFile ../../../../ssh-keys/age/${name}.pub);
  keys = [(read "work") (read "yubi")];
in {
}

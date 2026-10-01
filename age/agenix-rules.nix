let
  key = name: builtins.replaceStrings ["\n"] [""] (builtins.readFile ../ssh-keys/age/${name}.pub);
  to = hosts: {publicKeys = map key (hosts ++ ["yubi"]);};
in {
  "desktop/airvpn-wg.conf.age" = to ["desktop"];
  "desktop/mam.age" = to ["desktop"];
  "desktop/mam-vpn.age" = to ["desktop"];

  "deck-oled/hosts.age" = to ["deck-oled"];
  "deck-oled/wg.conf.age" = to ["deck-oled"];

  "shared/blocked-hosts.age" = to ["work" "deck-oled"];
}

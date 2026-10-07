let
  desktop = builtins.replaceStrings ["\n"] [""] (builtins.readFile ../ssh-keys/age/desktop.pub);
  deck-oled = builtins.replaceStrings ["\n"] [""] (builtins.readFile ../ssh-keys/age/deck-oled.pub);
  work = builtins.replaceStrings ["\n"] [""] (builtins.readFile ../ssh-keys/age/work.pub);
  yubi = builtins.replaceStrings ["\n"] [""] (builtins.readFile ../ssh-keys/age/yubi.pub);
in {
  # Desktop
  "desktop/airvpn-wg.conf.age".publicKeys = [yubi desktop];
  "desktop/mam.age".publicKeys = [yubi desktop];
  "desktop/mam-vpn.age".publicKeys = [yubi desktop];

  # Deck-oled
  "deck-oled/hosts.age".publicKeys = [yubi deck-oled];
  "deck-oled/wg.conf.age".publicKeys = [yubi deck-oled];

  # Work
  "work/ghcr-auth.age".publicKeys = [yubi work];

  # Shared
  "shared/blocked-hosts.age".publicKeys = [yubi desktop work deck-oled];
  "shared/tokens/CLAUDE_CODE_OAUTH_TOKEN.age".publicKeys = [yubi desktop work];
  "shared/tokens/GH_TOKEN.age".publicKeys = [yubi desktop work];
  "shared/tokens/LINEAR_API_KEY.age".publicKeys = [yubi desktop work];
  "shared/tokens/NOTION_TOKEN.age".publicKeys = [yubi desktop work];
}

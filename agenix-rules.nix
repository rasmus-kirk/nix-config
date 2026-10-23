let
  desktop = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./ssh-keys/age/desktop.pub);
  deck-oled = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./ssh-keys/age/deck-oled.pub);
  work = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./ssh-keys/age/work.pub);
  yubi = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./ssh-keys/age/yubi.pub);
in {
  # Desktop
  "age/desktop/airvpn-wg.conf.age".publicKeys = [yubi desktop];
  "age/desktop/mam.age".publicKeys = [yubi desktop];
  "age/desktop/mam-vpn.age".publicKeys = [yubi desktop];

  # Work
  "age/work/ghcr-auth.age".publicKeys = [yubi work];

  # Shared
  "age/shared/blocked-hosts.age".publicKeys = [yubi desktop work deck-oled];
  "age/shared/tokens/CLAUDE_CODE_OAUTH_TOKEN.age".publicKeys = [yubi desktop work];
  "age/shared/tokens/GH_TOKEN.age".publicKeys = [yubi desktop work];
  "age/shared/tokens/GRAFANA_TOKEN.age".publicKeys = [yubi work];
  "age/shared/tokens/LINEAR_API_KEY.age".publicKeys = [yubi work];
  "age/shared/tokens/NOTION_TOKEN.age".publicKeys = [yubi work];
  "age/shared/tokens/SLACK_TOKEN.age".publicKeys = [yubi work];
}

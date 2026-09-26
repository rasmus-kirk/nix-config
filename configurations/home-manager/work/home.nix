{
  pkgs,
  config,
  inputs,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  username = "user";

  # sudo must be the setuid wrapper, not the store path.
  devTerm = pkgs.writeShellApplication {
    name = "dev-term";
    runtimeInputs = [pkgs.foot];
    text = ''
      exec foot --app-id=dev-term --title=dev -- /run/wrappers/bin/sudo -u dev -i
    '';
  };
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      signKey = "${secretDir}/ssh/id_ed25519_yubi.pub";
      signPubKey = ../../../pubkeys/yubi.pub;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    jiten.enable = true;
    claude.enable = true;
    cosmic.enable = true;
    scripts.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh = {
      enable = true;
      addKeysToAgent = true;
      identityPath = "${secretDir}/ssh/id_ed25519_yubi";
      includes = ["/data/.state/ssh/remotes/*.conf"];
    };
    userDirs = {
      enable = true;
      rootDir = dataDir;
      mediaDirs = false;
      autoSortDownloads = true;
    };
    zathura = {
      enable = true;
      darkmode = false;
    };
    zsh = {
      enable = true;
      stateDir = stateDir;
    };
    fonts.enable = true;
    box = {
      enable = true;
      homeManagerPackage = inputs.self.homeConfigurations.sandbox.activationPackage;
    };
    chromiumLaunchers = {
      enable = true;
      stateDir = stateDir;
      launchers = {
        "Claude Chat" = "https://claude.ai/new";
        Youtube = "https://youtube.com/";
        "Proton Mail" = "https://mail.proton.me/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  systemd.user.tmpfiles.rules = [
    "L+ ${config.home.homeDirectory}/.mozilla                   - - - - ${stateDir}/firefox/home"
    "L+ ${config.home.homeDirectory}/.config/mozilla            - - - - ${stateDir}/firefox/config"
    "L+ ${config.home.homeDirectory}/.config/chromium           - - - - ${stateDir}/chromium"

    "L+ ${config.home.homeDirectory}/.local/state/cosmic        - - - - ${stateDir}/cosmic/local"
    "L+ ${config.home.homeDirectory}/.local/state/cosmic-comp   - - - - ${stateDir}/cosmic/comp"

    "L+ ${config.home.homeDirectory}/.claude                    - - - - ${stateDir}/claude/state"
    "L+ ${config.home.homeDirectory}/.claude.json               - - - - ${stateDir}/claude/claude.json"
  ];

  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ "$PWD" == "$HOME" ]]; then
        cd /data
      fi

      exec zsh
    '';
  };

  programs.zsh.profileExtra = ''
    export TERM=foot
    # GitHub PAT for the github MCP plugin when Claude Code runs on host.
    # In the box, ~/.secret/github/pat is exported via the sandbox initScript;
    # this mirrors that behaviour for host shells.
    if [ -r ${secretDir}/github/qms-pat-global-ro ]; then
      export GITHUB_PERSONAL_ACCESS_TOKEN="$(tr -d '[:space:]' < ${secretDir}/github/qms-pat-global-ro)"
    fi
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home.packages = with pkgs; [
    claude-code
    bubblewrap
    finamp
    devTerm
  ];
}

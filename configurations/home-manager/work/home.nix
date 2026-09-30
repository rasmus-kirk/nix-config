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
      yubiHandle = "${secretDir}/ssh/id_ed25519_yubi";
      tokenDir = "${secretDir}/tokens-read-only";
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
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home.packages = with pkgs; [
    devTerm
  ];
}

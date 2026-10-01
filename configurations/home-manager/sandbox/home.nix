{
  pkgs,
  lib,
  config,
  boxUser,
  ...
}: let
  dataDir = "/data";
  secretDir = "${dataDir}/.secret";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  # Set by the flake's mkSandbox, from kirk.box.user on the host side.
  username = boxUser;
  machine = "sandbox";
in {
  kirk = {
    terminalTools.enable = true;
    xdgMime.enable = true;
    git = {
      enable = true;
      signKey = "/home/${username}/.ssh/id_ed25519_yubi.pub";
      signPubKey = ../../../ssh-keys/yubi.pub;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    homeManagerScripts = {
      enable = true;
      extraNixOptions = true;
      configDir = configDir;
      machine = machine;
    };
    jiten.enable = false;
    scripts.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh.enable = true;
    userDirs = {
      enable = true;
      rootDir = dataDir;
      autoSortDownloads = true;
    };
    zsh = {
      enable = true;
      tokenDir = "/home/${username}/.secret/tokens-read-only";
    };
    claudeConfig.notion.enable = true;
    claudeConfig.mcpServers.linear = {
      type = "http";
      url = "https://mcp.linear.app/mcp";
      headers.Authorization = "Bearer \${LINEAR_API_KEY}";
    };
  };

  systemd.user.startServices = false;

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      exec ${lib.getExe pkgs.zsh}
    '';
  };

  programs.zsh.profileExtra = ''
    # Yazi
    export TERM=foot
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
    # Always trust any direnv in the box.
    config.whitelist.prefix = ["/"];
  };

  home.packages = with pkgs; [
    coreutils
    python3
    findutils
    gawk
    gnugrep
    gnused
    less
    nix

    curl

    wl-clipboard
  ];
}

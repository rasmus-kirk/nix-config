# My home manager config
{
  pkgs,
  config,
  ...
}: let
  secretDir = "${config.home.homeDirectory}/.secret";
  configDir = "${config.home.homeDirectory}/.system-configuration";
  username = "user";
  machine = "work";
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    xdgMime.enable = true;
    monero.enable = true;
    git = {
      enable = true;
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
    jiten.enable = true;
    scripts.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    ssh = {
      enable = true;
      identityPath = "${secretDir}/id_ed25519";
    };
    userDirs = {
      enable = true;
      autoSortDownloads = true;
    };
    zathura = {
      enable = true;
      darkmode = false;
    };
    zsh.enable = true;
    rustle.enable = true;
    fonts.enable = true;
    chromiumLaunchers = {
      enable = true;
      launchers = {
        mattermost = "https://mattermost.cs.au.dk/";
        discord = "https://discord.com/app";
        slack = "https://concordium.slack.com/";
        grok = "https://grok.com/";
        chat-gpt = "https://chatgpt.com/";
      };
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  services = {
    syncthing.enable = true;
    podman.enable = true;
  };

  programs.bash = {
    enable = true;
    profileExtra = ''
      # Fix programs not showing up
      export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

      export NIX_PATH=''${NIX_PATH:+$NIX_PATH:}$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
    '';

    initExtra = "exec zsh";
  };

  programs.zsh.profileExtra = ''
    # export PATH=$PATH:~/.cargo/bin:~/.local/bin

    # Yazi
    export TERM=foot

    export XCURSOR_THEME="Capitaine Cursors (Gruvbox)"
    export XCURSOR_PATH="$XCURSOR_PATH":/usr/share/icons:~/.local/share/icons
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home.packages = with pkgs; [
    # Misc
    keepassxc
    thunderbird

    (pkgs.writeShellApplication {
      name = "screenshot";
      runtimeInputs = with pkgs; [ slurp grim ];
      text = ''
        mkdir -p "$HOME"/.local/state
        slurp | grim -g - "$HOME"/.local/state/kanji/"$(date +%s)".png
      '';
    })

    # Browsers
    librewolf
    chromium

    # Media
    qbittorrent

    # Chat
    signal-desktop-bin

    # Misc Terminal Tools
    wl-clipboard
    yt-dlp
  ];
}

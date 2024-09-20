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
    fzf.enable = true;
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix.enable = true;
    homeManagerScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
    jiten.enable = true;
    scripts.enable = true;
    joshuto.enable = true;
    joshuto.enableZshIntegration = false;
    kakoune.enable = true;
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
    fonts.enable = true;
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;

  services.syncthing.enable = true;

  nix = {
    package = pkgs.nixVersions.latest;
    settings.experimental-features = ["nix-command" "flakes"];
    settings.trusted-users = [
      username
      "@wheel"
    ];
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

  programs.yazi = let
    mkYaziPlugin = name:
      pkgs.stdenv.mkDerivation {
        name = name;
        phases = ["unpackPhase" "buildPhase"];
        buildPhase = ''
          mkdir -p "$out"
          cp -r "${name}".yazi/* "$out"
        '';
        src = pkgs.fetchgit {
          rev = "5e65389d1308188e5a990059c06729e2edb18f8a";
          url = "https://github.com/yazi-rs/plugins.git";
          hash = "sha256-XHaQjudV9YSMm4vF7PQrKGJ078oVF1U1Du10zXEJ9I0=";
        };
      };
    gruvbox-dark = pkgs.stdenv.mkDerivation {
      name = "gruvbox-dark";
      phases = ["unpackPhase" "buildPhase"];
      buildPhase = "mkdir -p $out ; cp -r . $out";
      src = pkgs.fetchgit {
        url = "https://github.com/bennyyip/gruvbox-dark.yazi.git";
        rev = "c204853de7a78bc99ea628e51857ce65506468db";
        hash = "sha256-NBco10MINyAJk1YWHwYUzvI9mnTJl9aYyDtQSTUP3Hs=";
      };
    };
  in {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "j";
    initLua = ''
      require("full-border"):setup()
      require("git"):setup()
    '';
    keymap = {
      manager.prepend_keymap = [
        {
          on = "e";
          run = "shell --interactive --block $EDITOR $0";
          desc = "Edit file";
        }
        # Selection
        {
          on = ";";
          run = "escape --select";
          desc = "Deselect all files";
        }
        {
          on = "?";
          run = "help";
          desc = "View help";
        }
        {
          on = "%";
          run = "select_all --state=true";
          desc = "Select all files";
        }
        {
          on = "J";
          run = ["select --state=none" "arrow 1"];
          desc = "Select down";
        }
        {
          on = "K";
          run = ["select --state=none" "arrow -1"];
          desc = "Select up";
        }
        # Plugins
        {
          on = "'";
          run = "plugin smart-filter";
          desc = "Smart filter";
        }
        {
          on = ["c" "m"];
          run = "plugin chmod";
          desc = "Chmod on selected files";
        }
        {
          on = "t";
          run = "plugin --sync hide-preview";
          desc = "Hide or show preview";
        }
        {
          on = "T";
          run = "plugin --sync max-preview";
          desc = "Maximize or restore preview";
        }
        # Goto
        {
          on = ["g" "~"];
          run = "cd ~";
          desc = "Goto home dir";
        }
        {
          on = ["g" "`"];
          run = "cd /";
          desc = "Goto root directory";
        }
        {
          on = ["g" "e"];
          run = "arrow 99999999999";
          desc = "Move cursor to bottom";
        }
        # Bookmarks
        {
          on = ["b" "u"];
          run = "cd $XDG_DOWNLOAD_DIR";
          desc = "Goto bookmarked download directory";
        }
        {
          on = ["b" "b"];
          run = "cd ~/media/books";
          desc = "Goto bookmarked books directory";
        }
        {
          on = ["b" "p"];
          run = "cd ~/media/documents/programming";
          desc = "Goto bookmarked programming directory";
        }
        {
          on = ["b" "a"];
          run = "cd ~/media/audio";
          desc = "Goto bookmarked audio directory";
        }
        {
          on = ["b" "a"];
          run = "cd $XDG_VIDEOS_DIR";
          desc = "Goto bookmarked videos directory";
        }
        {
          on = ["b" "d"];
          run = "cd $XDG_DOCUMENTS_DIR";
          desc = "Goto bookmarked download directory";
        }
        {
          on = ["b" "s"];
          run = "cd ~/media/documents/study";
          desc = "Goto bookmarked study directory";
        }
        {
          on = ["b" "i"];
          run = "cd $XDG_PICTURES_DIR";
          desc = "Goto bookmarked images directory";
        }
      ];
    };
    settings = {
      plugin.prepend_fetchers = [
        {
          id = "git";
          name = "*/";
          run = "git";
        }
        {
          id = "git";
          name = "*";
          run = "git";
        }
      ];
    };
    flavors.gruvbox-dark = gruvbox-dark;
    plugins = {
      full-border = mkYaziPlugin "full-border";
      git = mkYaziPlugin "git";
      smart-filter = mkYaziPlugin "smart-filter";
      chmod = mkYaziPlugin "chmod";
      hide-preview = mkYaziPlugin "hide-preview";
      max-preview = mkYaziPlugin "max-preview";
    };
    theme.flavor.use = "gruvbox-dark";
  };

  programs.emacs = {
    enable = true;
    extraConfig = ''
      (use-package kakoune)
    '';
    extraPackages = epkgs: [epkgs.kakoune];
  };

  # TODO: Add to kirk-module
  programs.mpv = {
    enable = true;
    bindings = {
      UP = "add chapter 1";
      DOWN = "add chapter -1";
      ESC = "quit";
      ENTER = "cycle pause";
      f = "cycle fullscreen";
      h = "seek -5";
      j = "add chapter -1";
      k = "add chapter 1";
      l = "seek 5";

      "Shift+LEFT" = "cycle sub down";
      "Shift+RIGHT" = "cycle sub";
      "Shift+UP" = "cycle audio";
      "Shift+DOWN" = "cycle audio down";

      y = "add audio-delay 0.010";
      o = "add audio-delay -0.010";

      i = ''cycle-values vf "sub,lavfi=negate" ""'';
      S = "playlist-shuffle";

      a = "ab-loop";

      "Alt+r" = "playlist-shuffle";
    };
    scripts = with pkgs.mpvScripts; [
      # Load all files in directory to playlist, playing next alphabetically ordered file on playback end.
      autoload
      # Better UI
      uosc
      # Allows media playback buttons to work in mpv
      mpris
      # Thumbnail support, needs uosc to work
      thumbfast
      # Prevents screen sleep on gnome
      inhibit-gnome
    ];
    config = {
      # TODO: wtf is the reason for this? It should not be necessary. WHY DOES IT WORK!?
      vo = "x11";

      alang = ["jpn" "eng"];
      slang = ["eng"];
      #extension.gif = {
      #  cache = "no";
      #  no-pause = "";
      #  loop-file = "yes";
      #};
      #extension.webm = {
      #  no-pause = "";
      #  loop-file = "yes";
      #};
    };
  };

  programs.zsh.profileExtra = ''
    export PATH=$PATH:~/.cargo/bin:~/.local/bin

    # Yazi
    export TERM=foot

    # Fix weird cargo concordium bug
    export LD_LIBRARY_PATH="${pkgs.zlib}/lib:$LD_LIBRARY_PATH";

    # Fix nix programs not showing up in gnome menus:
    #export XDG_DATA_DIRS="$HOME/.nix-profile/share:$XDG_DATA_DIRS"

    export XCURSOR_THEME="Capitaine Cursors (Gruvbox)"
    export XCURSOR_PATH="$XCURSOR_PATH":/usr/share/icons:~/.local/share/icons
  '';

  home.packages = with pkgs; [
    # Misc
    gnome-tweaks
    keepassxc
    thunderbird
    yarn

    # Browsers
    librewolf
    chromium

    # Media
    qbittorrent
    #mpv

    # Crytpo
    monero-gui

    # Chat
    slack
    signal-desktop

    # Fonts
    (nerdfonts.override {fonts = ["FiraCode"];})
    fira-code

    # Document handling
    texlive.combined.scheme-full
    pandoc
    inotify-tools

    # Misc Terminal Tools
    wl-clipboard
    yt-dlp
  ];
}

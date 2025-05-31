{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.yazi;
  mkYaziPlugin = name:
    pkgs.stdenv.mkDerivation {
      name = name;
      phases = ["unpackPhase" "buildPhase"];
      buildPhase = ''
        mkdir -p "$out"
        echo "${name}.yazi/*" "$out"
        cp -vr ${name}.yazi/* "$out"
      '';
      src = pkgs.fetchgit {
        rev = "63f9650e522336e0010261dcd0ffb0bf114cf912";
        url = "https://github.com/yazi-rs/plugins.git";
        hash = "sha256-ZCLJ6BjMAj64/zM606qxnmzl2la4dvO/F5QFicBEYfU=";
      };
    };
  mkYaziPluginGithub = x:
    pkgs.stdenv.mkDerivation {
      name = x.name;
      phases = ["unpackPhase" "buildPhase"];
      buildPhase = ''
        mkdir -p "$out"
        ls .
        echo "$out"
        cp -vr . "$out"
      '';
      src = pkgs.fetchgit {
        rev = x.rev;
        url = x.url;
        hash = x.hash;
      };
    };
  plugins = {
    gruvbox-dark = mkYaziPluginGithub {
      name = "gruvbox-dark";
      url = "https://github.com/bennyyip/gruvbox-dark.yazi.git";
      rev = "91fdfa70f6d593934e62aba1e449f4ec3d3ccc90";
      hash = "sha256-RWqyAdETD/EkDVGcnBPiMcw1mSd78Aayky9yoxSsry4=";
    };
    exifaudio = mkYaziPluginGithub {
      name = "exifaudio";
      url = "https://github.com/Sonico98/exifaudio.yazi";
      rev = "7ff714155f538b6460fdc8e911a9240674ad9b89";
      hash = "sha256-qRUAKlrYWV0qzI3SAQUYhnL3QR+0yiRc+0XbN/MyufI=";
    };
  };
in {
  options.kirk.yazi = {
    enable = mkEnableOption "yazi file manager";

    configDir = mkOption {
      type = with types; nullOr path;
      default = null;

      description = ''
        The path to the nix configuration directory.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      exiftool
      mediainfo
      ffmpegthumbnailer
      jq
      poppler
      fd
      ripgrep
      fzf
      imagemagick
      libsixel
    ];

    programs.yazi = {
      enable = cfg.enable;
      enableZshIntegration = true;
      shellWrapperName = "j";
      initLua = ''
        require("git"):setup()
        require("full-border"):setup()
        require("session"):setup {
          sync_yanked = true,
        }
      '';
      keymap = {
        mgr.prepend_keymap =
          [
            {
              on = "!";
              run = "tab_create --current";
              desc = "Open new tab";
            }
            {
              on = "@";
              run = "close";
              desc = "Close tab";
            }
            {
              on = "e";
              run = ''shell --block --confirm "$EDITOR $0"'';
              desc = "Open the selected files in editor";
            }
            {
              on = ["m" "d"];
              run = "plugin mkdir";
              desc = "Create a directory";
            }
            {
              on = ["m" "f"];
              run = "create";
              desc = "Create a file";
            }
            {
              on = ["m" "t"];
              run = ''shell "foot </dev/null &>/dev/null &"'';
              desc = "Create a new terminal";
            }
            {
              on = ["m" "j"];
              run = ''shell "foot </dev/null &>/dev/null zsh -c 'source ~/.zshrc; j; zsh'& "'';
              desc = "Create a new terminal with yazi open";
            }
            {
              on = ["1"];
              run = "plugin autotab 1";
            }
            {
              on = ["2"];
              run = "plugin autotab 2";
            }
            {
              on = ["3"];
              run = "plugin autotab 3";
            }
            {
              on = ["4"];
              run = "plugin autotab 4";
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
              run = "toggle_all --state=true";
              desc = "Select all files";
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
              run = "plugin toggle-preview";
              desc = "Hide or show preview";
            }
            {
              on = "T";
              run = "plugin toggle-pane";
              desc = "Maximize or restore preview";
            }
            # Goto
            {
              on = ["~"];
              run = "cd ~";
              desc = "Goto home dir";
            }
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
              run = "arrow bot";
              desc = "Move cursor to bottom";
            }
            # Bookmarks
            {
              on = ["b" "u"];
              run = "cd $XDG_DOWNLOAD_DIR";
              desc = "Goto download dir";
            }
            {
              on = ["b" "b"];
              run = "cd ~/media/books";
              desc = "Goto books dir";
            }
            {
              on = ["b" "p"];
              run = "cd ~/media/documents/programming";
              desc = "Goto programming dir";
            }
            {
              on = ["b" "a"];
              run = "cd ~/media/audio";
              desc = "Goto audio dir";
            }
            {
              on = ["b" "a"];
              run = "cd $XDG_VIDEOS_DIR";
              desc = "Goto videos dir";
            }
            {
              on = ["b" "d"];
              run = "cd $XDG_DOCUMENTS_DIR";
              desc = "Goto download dir";
            }
            {
              on = ["b" "s"];
              run = "cd ~/media/documents/study";
              desc = "Goto study dir";
            }
            {
              on = ["b" "i"];
              run = "cd $XDG_PICTURES_DIR";
              desc = "Goto images dir";
            }
          ]
          ++ (lib.optional (cfg.configDir != null) {
            on = ["b" "n"];
            run = "cd ${cfg.configDir}";
            desc = "Goto nix config dir";
          });
      };
      settings = {
        #opener = {
        #  xdg = [
        #    { run = ''xdg-open "$@"''; desc = "xdg-open"; for = "unix"; }
        #  ];
        #};
        #open.prepend_rules = [
        #  { mime = "*"; use = "xdg"; }
        #];
        plugin = {
          prepend_previewers = [
            {
              mime = "audio/*";
              run = "exifaudio";
            }
          ];
          prepend_fetchers = [
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
      };
      flavors.gruvbox-dark = plugins.gruvbox-dark;
      plugins = {
        mkdir = ./plugins/mkdir;
        autotab = ./plugins/autotab;
        exifaudio = plugins.exifaudio;
        full-border = mkYaziPlugin "full-border";
        git = mkYaziPlugin "git";
        smart-filter = mkYaziPlugin "smart-filter";
        chmod = mkYaziPlugin "chmod";
        toggle-pane= mkYaziPlugin "toggle-pane";
      };
      theme.flavor.use = "gruvbox-dark";
    };
  };
}

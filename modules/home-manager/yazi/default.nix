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
        cp -r "${name}".yazi/* "$out"
      '';
      src = pkgs.fetchgit {
        rev = "a1b678dfacfd2726fad364607aeaa7e1fded3cfa";
        url = "https://github.com/yazi-rs/plugins.git";
        hash = "sha256-Vvq7uau+UNcriuLE7YMK5rSOXvVaD0ElT59q+09WwdQ=";
      };
    };
  mkYaziPluginGithub = x:
    pkgs.stdenv.mkDerivation {
      name = x.name;
      phases = ["unpackPhase" "buildPhase"];
      buildPhase = ''
        mkdir -p "$out"
        cp -r . "$out"
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
      rev = "b4cc9f2a3016f9b5a9bbb5aeb4619d029ee61397";
      hash = "sha256-9ZZHXP0Junaj6r80nE8oDNEU5WIKVdtz4g72BFzcSAM=";
    };
    exifaudio = mkYaziPluginGithub {
      name = "exifaudio";
      url = "https://github.com/Sonico98/exifaudio.yazi";
      rev = "de526f336dfed54c8545d1e445cb8511e195fecd";
      hash = "sha256-s+WPSUfHNuS+xVgtPjjIOFMuu+mAUD6j7jsiZmZpcf0=";
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
        manager.prepend_keymap =
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
              run = "plugin hide-preview";
              desc = "Hide or show preview";
            }
            {
              on = "T";
              run = "plugin max-preview";
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
        hide-preview = mkYaziPlugin "hide-preview";
        max-preview = mkYaziPlugin "max-preview";
      };
      theme.flavor.use = "gruvbox-dark";
    };
  };
}

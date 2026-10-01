{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.yazi;
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
      rev = "619fdc5844db0c04f6115a62cf218e707de2821e";
      hash = "sha256-Y/i+eS04T2+Sg/Z7/CGbuQHo5jxewXIgORTQm25uQb4=";
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
      dragon-drop
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
              on = ["a" "d"];
              run = "shell -- dragon-drop -x -i -T %h";
              desc = "Drag and drop";
            }
            {
              on = ["m" "f"];
              run = "create";
              desc = "Create a file";
            }
            {
              on = ["m" "d"];
              run = "plugin mkdir";
              desc = "Create a directory";
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
              run = "plugin toggle-pane min-preview";
              desc = "Hide or show preview";
            }
            {
              on = "T";
              run = "plugin toggle-pane max-preview";
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
              run = "cd /data/media/books";
              desc = "Goto books dir";
            }
            {
              on = ["b" "p"];
              run = "cd /data/media/documents/programming";
              desc = "Goto programming dir";
            }
            {
              on = ["b" "a"];
              run = "cd /data/media/audio";
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
              run = "cd /data/media/documents/study";
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
        preview = {
          max_width = 3840;
          max_height = 2160;
        };
        plugin = {
          prepend_fetchers = [
            {
              url = "*/";
              run = "git";
              group = "git";
            }
            {
              url = "*";
              run = "git";
              group = "git";
            }
          ];
        };
      };
      flavors.gruvbox-dark = plugins.gruvbox-dark;
      plugins = {
        mkdir = ./plugins/mkdir;
        autotab = ./plugins/autotab;
        full-border = pkgs.yaziPlugins.full-border;
        git = pkgs.yaziPlugins.git;
        smart-filter = pkgs.yaziPlugins.smart-filter;
        chmod = pkgs.yaziPlugins.chmod;
        toggle-pane = pkgs.yaziPlugins.toggle-pane;
      };
      theme.flavor.use = "gruvbox-dark";
    };
  };
}

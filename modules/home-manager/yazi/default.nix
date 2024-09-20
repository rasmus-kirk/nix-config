{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.yazi;
  gruvbox-dark = pkgs.stdenv.mkDerivation {
    name = "gruvbox-dark";
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      mkdir -p "$out"
      cp -r . "$out"
    '';
    src = pkgs.fetchgit {
      url = "https://github.com/bennyyip/gruvbox-dark.yazi.git";
      rev = "c204853de7a78bc99ea628e51857ce65506468db";
      hash = "sha256-NBco10MINyAJk1YWHwYUzvI9mnTJl9aYyDtQSTUP3Hs=";
    };
  };
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
in {
  options.kirk.yazi = {
    enable = mkEnableOption "yazi file manager";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
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
  };
}

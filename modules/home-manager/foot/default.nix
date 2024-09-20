{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.foot;
in {
  options.kirk.foot = {
    enable = mkEnableOption "foot terminal emulator";

    colorscheme = mkOption {
      type = types.attrs;
      default = config.kirk.gruvbox.colorscheme;
      description = "A colorscheme attribute set.";
    };

    alpha = mkOption {
      type = types.float;
      default = 0.85;
      description = "Alpha value of the foot terminal.";
    };

    fontSize = mkOption {
      type = types.int;
      default = 15;
      description = "Font size of the terminal.";
    };

    enableKeyBindings = mkOption {
      type = types.bool;
      default = true;
      description = "Whether or not to enable my keybindings.";
    };
  };

  config = mkIf cfg.enable {
    programs.foot = {
      enable = true;
      settings = {
        main = {
          term = "xterm-256color";
          font = "monospace:pixelsize=" + toString (cfg.fontSize);
        };
        colors = mkMerge [
          {
            alpha = cfg.alpha;
          }
          (mkIf (cfg.colorscheme != {}) {
            background = cfg.colorscheme.bg;
            foreground = cfg.colorscheme.fg;
            regular0 = cfg.colorscheme.black;
            regular1 = cfg.colorscheme.red;
            regular2 = cfg.colorscheme.green;
            regular3 = cfg.colorscheme.yellow;
            regular4 = cfg.colorscheme.blue;
            regular5 = cfg.colorscheme.purple;
            regular6 = cfg.colorscheme.teal;
            regular7 = cfg.colorscheme.white;
            bright0 = cfg.colorscheme.bright.black;
            bright1 = cfg.colorscheme.bright.red;
            bright2 = cfg.colorscheme.bright.green;
            bright3 = cfg.colorscheme.bright.yellow;
            bright4 = cfg.colorscheme.bright.blue;
            bright5 = cfg.colorscheme.bright.purple;
            bright6 = cfg.colorscheme.bright.teal;
            bright7 = cfg.colorscheme.bright.white;
          })
        ];
        key-bindings = mkIf cfg.enableKeyBindings {
          "scrollback-up-half-page" = "Mod1+Shift+K";
          "scrollback-up-line" = "Mod1+K";
          "scrollback-down-half-page" = "Mod1+Shift+J";
          "scrollback-down-line" = "Mod1+J";
          "clipboard-copy" = "Mod1+C Control+Shift+C";
          "clipboard-paste" = "Mod1+V Control+Shift+V";
          "font-increase" = "Mod1+plus Mod1+equal Control+KP_Add";
          "font-decrease" = "Mod1+minus Control+KP_Subtract";
          "search-start" = "Mod1+f";
        };
        search-bindings = mkIf cfg.enableKeyBindings {
          "find-next" = "Mod1+n";
          "find-prev" = "Mod1+N";
        };
      };
    };
  };
}

{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.zathura;

  # Convert a hex color string to RGBA
  hexToRgba = hexStr: alpha: let
    # Helper function to convert a single hex digit to its integer value
    hexDigitToInt = digit: lib.lists.findFirstIndex (x: x == digit) null ["0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f" "A" "B" "C" "D" "E" "F"];

    # Function to convert a hex pair to an integer
    hexPairToInt = stringPair: let
      pair = lib.strings.stringToCharacters stringPair;
    in
      (hexDigitToInt (builtins.elemAt pair 0)) * 16 + (hexDigitToInt (builtins.elemAt pair 1));

    hex =
      if builtins.substring 0 1 hexStr == "#"
      then builtins.substring 1 (builtins.stringLength hexStr - 1) hexStr
      else hexStr;
    red = builtins.toString (hexPairToInt (builtins.substring 0 2 hex));
    green = builtins.toString (hexPairToInt (builtins.substring 2 4 hex));
    blue = builtins.toString (hexPairToInt (builtins.substring 4 6 hex));
  in "rgba(${red}, ${green}, ${blue}, ${builtins.toString alpha})";
in {
  options.kirk.zathura = {
    enable = mkEnableOption "foot terminal emulator";

    colorscheme = mkOption {
      type = types.attrs;
      default = config.kirk.gruvbox.colorscheme;

      description = ''
        A colorscheme attribute set.
      '';
    };

    darkmode = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Enable darkmode on recolor.
      '';
    };

    enableKeyBindings = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Whether or not to enable my keybindings.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.zathura = {
      enable = true;

      options = mkMerge [
        {
          selection-clipboard = "clipboard";
          recolor-reverse-video = "true";
          recolor-keephue = "true";
        }
        (mkIf (cfg.colorscheme != {} && !cfg.darkmode) {
          default-bg = "#${cfg.colorscheme.bg}";
          default-fg = "#${cfg.colorscheme.fg}";
          statusbar-fg = "#${cfg.colorscheme.fg}";
          statusbar-bg = "#${cfg.colorscheme.black}";
          inputbar-bg = "#${cfg.colorscheme.bg}";
          inputbar-fg = "#${cfg.colorscheme.white}";
          notification-bg = "#${cfg.colorscheme.fg}";
          notification-fg = "#${cfg.colorscheme.bg}";
          notification-error-bg = "#${cfg.colorscheme.red}";
          notification-error-fg = "#${cfg.colorscheme.fg}";
          notification-warning-bg = "#${cfg.colorscheme.yellow}";
          notification-warning-fg = "#${cfg.colorscheme.fg}";
          highlight-color = hexToRgba cfg.colorscheme.yellow 0.5;
          highlight-active-color = hexToRgba cfg.colorscheme.green 0.5;
          recolor-lightcolor = "#${cfg.colorscheme.bright.fg}";
          recolor-darkcolor = "#${cfg.colorscheme.bg}";
        })
        (mkIf (cfg.colorscheme != {} && cfg.darkmode) {
          default-bg = "#${cfg.colorscheme.bg}";
          default-fg = "#${cfg.colorscheme.fg}";
          statusbar-fg = "#${cfg.colorscheme.fg}";
          statusbar-bg = "#${cfg.colorscheme.black}";
          inputbar-bg = "#${cfg.colorscheme.bg}";
          inputbar-fg = "#${cfg.colorscheme.white}";
          notification-bg = "#${cfg.colorscheme.fg}";
          notification-fg = "#${cfg.colorscheme.bg}";
          notification-error-bg = "#${cfg.colorscheme.red}";
          notification-error-fg = "#${cfg.colorscheme.fg}";
          notification-warning-bg = "#${cfg.colorscheme.yellow}";
          notification-warning-fg = "#${cfg.colorscheme.fg}";
          highlight-color = hexToRgba cfg.colorscheme.yellow 0.5;
          highlight-active-color = hexToRgba cfg.colorscheme.green 0.5;
          recolor-lightcolor = "#${cfg.colorscheme.bg}";
          recolor-darkcolor = "#${cfg.colorscheme.fg}";
        })
      ];

      mappings = mkIf cfg.enableKeyBindings {
        f = "toggle_fullscreen";
        r = "reload";
        R = "rotate";
        H = "navigate previous";
        K = "zoom out";
        J = "zoom in";
        L = "navigate next";
        i = "recolor";
        "<A-n>" = "search backward";
        "<Right>" = "navigate next";
        "<Left>" = "navigate previous";
        "[fullscreen] f" = "toggle_fullscreen";
        "[fullscreen] r" = "reload";
        "[fullscreen] R" = "rotate";
        "[fullscreen] H" = "navigate -1";
        "[fullscreen] K" = "zoom out";
        "[fullscreen] J" = "zoom in";
        "[fullscreen] L" = "navigate 1";
        "[fullscreen] i" = "recolor";
        "[fullscreen] <Right>" = "navigate next";
        "[fullscreen] <Left>" = "navigate previous";
      };
    };
  };
}

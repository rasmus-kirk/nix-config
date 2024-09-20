{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.fzf;
in {
  options.kirk.fzf = {
    enable = mkEnableOption "foot terminal emulator";

    colorscheme = mkOption {
      type = types.attrs;
      default = config.kirk.gruvbox.colorscheme;
      description = "A colorscheme attribute set.";
    };

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable zsh integration.";
    };
  };

  config = mkIf cfg.enable {
    programs.fzf = {
      enable = true;
      enableZshIntegration = cfg.enableZshIntegration;

      colors = mkIf (cfg.colorscheme != {}) {
        "fg" = "#${cfg.colorscheme.fg}";
        "fg+" = "#${cfg.colorscheme.white}";
        "bg" = "#${cfg.colorscheme.bg}";
        "bg+" = "#${cfg.colorscheme.black}";
        "hl" = "#${cfg.colorscheme.blue}";
        "hl+" = "#${cfg.colorscheme.bright.blue}";
        "info" = "#${cfg.colorscheme.bright.white}";
        "marker" = "#${cfg.colorscheme.green}";
        "prompt" = "#${cfg.colorscheme.red}";
        "spinner" = "#${cfg.colorscheme.purple}";
        "pointer" = "#${cfg.colorscheme.purple}";
        "header" = "#${cfg.colorscheme.blue}";
      };
    };
  };
}

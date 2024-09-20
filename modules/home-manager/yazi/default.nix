{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.joshuto;
  yaziPkgs = {
    full-border = stdenv.mkDerivation {
      name = "full-border";
      src = fetchgit {
        url = "https://github.com/yazi-rs/plugins.git";
        sparseCheckout = ["full-border.yazi"];
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    };
    gruvbox-dark = stdenv.mkDerivation {
      name = "gruvbox-dark";
      src = fetchgit {
        url = "https://github.com/bennyyip/gruvbox-dark.yazi.git";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    };
  };
in {
  options.kirk.joshuto = {
    enable = mkEnableOption "yazi file manager";

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Adds the auto-cd `j` command to zsh.
      '';
    };
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
      enable = true;
      enableZshIntegration = cfg.enableZshIntegration;
      flavors.gruvbox-dark = yaziPkgs.gruvbox-dark;
      plugins = {
        full-border = yaziPkgs.full-border;
      };
      theme.flavor.use = "gruvbox-dark";
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.kotofetch;
  colors = config.kirk.gruvbox.colorscheme;
in {
  options.kirk.kotofetch = {
    enable = mkEnableOption "daily japanese quote from kotofetch";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [kotofetch];

    programs.zsh.initContent = ''
      if [[ -z "$KOTOFETCH_DISPLAYED" ]]; then
        export KOTOFETCH_DISPLAYED=true
        ${pkgs.kotofetch}/bin/kotofetch \
          --translation furigana,english \
          --furigana-position above \
          --vertical-padding 0 \
          --quote-color "#${colors.yellow}" \
          --translation-color "#${colors.white}" \
          --border-color "#${colors.green}" \
          --bold true \
          --animation scramble \
          --animation-duration-ms 500 \
          --seed "$(date +%Y%m%d)"
      fi
    '';
  };
}

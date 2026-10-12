{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.kotofetch;
  colors = config.kirk.gruvbox.colorscheme;

  quote-of-the-day = pkgs.writeShellApplication {
    name = "quote-of-the-day";

    runtimeInputs = with pkgs; [kotofetch gnused coreutils];
    inheritPath = false;

    text = ''
      CLICOLOR_FORCE=1 kotofetch \
        --translation furigana,english \
        --furigana-position above \
        --vertical-padding 0 \
        --centered false \
        --quote-color "#${colors.yellow}" \
        --translation-color "#${colors.white}" \
        --border-color "#${config.kirk.gruvbox.lightColorscheme.bright.green}" \
        --bold true \
        --seed "$(date +%Y%m%d)" |
        sed -u 's/^/    /'
    '';
  };
in {
  options.kirk.kotofetch = {
    enable = mkEnableOption "daily japanese quote from kotofetch";
  };

  config = mkIf cfg.enable {
    programs.zsh.initContent = ''
      if [[ -z "$KOTOFETCH_DISPLAYED" ]]; then
        export KOTOFETCH_DISPLAYED=true
        ${getExe quote-of-the-day}
      fi
    '';
  };
}

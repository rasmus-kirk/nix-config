{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.cosmic;
in {
  options.kirk.cosmic.enable = mkEnableOption "declarative COSMIC desktop configuration";

  config = mkIf cfg.enable {
    xdg.configFile."cosmic" = {
      source = ./config;
      recursive = true;
      force = true;
    };
  };
}

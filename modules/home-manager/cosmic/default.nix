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
    home.activation.cosmicConfig = hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -p ${config.xdg.configHome}/cosmic
      run cp -rT --remove-destination --no-preserve=mode ${./config} ${config.xdg.configHome}/cosmic
    '';
  };
}

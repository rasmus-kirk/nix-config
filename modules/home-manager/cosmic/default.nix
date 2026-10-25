{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.cosmic;
in {
  options.kirk.cosmic.enable = mkEnableOption "declarative COSMIC desktop configuration";

  config = mkIf cfg.enable {
    home.packages = [pkgs.wtype];

    home.activation.cosmicConfig = hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -p ${config.xdg.configHome}/cosmic
      run ${getExe pkgs.rsync} -r --checksum --chmod=Du+rwx,Fu+rw ${./config}/ ${config.xdg.configHome}/cosmic/
    '';
  };
}

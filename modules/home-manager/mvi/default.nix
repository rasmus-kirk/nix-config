{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.mvi;
  mviConfig = pkgs.stdenv.mkDerivation {
    name = "mviConfig";
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      mkdir -p "$out"
      cp -r . "$out"
    '';
    src = pkgs.fetchgit {
      rev = "efc82147cba4809f22e9afae6ed7a41ad9794ffd";
      url = "https://github.com/occivink/mpv-image-viewer.git";
      hash = "sha256-H7uBwrIb5uNEr3m+rHED/hO2CHypGu7hbcRpC30am2Q=";
    };
  };
  mviPackage = pkgs.writeShellScriptBin "mvi" ''
    mpv --config-dir="''${XDG_CONFIG_HOME:-''${HOME}/.config}/mvi" "$@"
  '';
in {
  options.kirk.mvi = {
    enable = mkEnableOption "mvi - the mpv image viewer";
    package = mkOption {
      type = types.package;
      default = mviPackage;
      description = "The mvi package to use.";
    };
  };

  config = mkIf cfg.enable {
    xdg.configFile."mvi".source = mviConfig;

    home.packages = [
      mviPackage
    ];
  };
}

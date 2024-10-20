{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.mpv;
in {
  options.kirk.mpv = {
    enable = mkEnableOption "mpv";

    vo = mkOption {
      type = types.str;
      default = "x11";
      description = ''Set the video output in the MPV config, must be "x11" on my work laptop for some reason, hence the default option.'';
    };
  };

  config = mkIf cfg.enable {
    programs.mpv = {
      enable = true;
      bindings = {
        UP = "add chapter 1";
        DOWN = "add chapter -1";
        ESC = "quit";
        ENTER = "cycle pause";
        f = "cycle fullscreen";
        h = "seek -5";
        j = "add chapter -1";
        k = "add chapter 1";
        l = "seek 5";

        "Shift+LEFT" = "cycle sub down";
        "Shift+RIGHT" = "cycle sub";
        "Shift+UP" = "cycle audio";
        "Shift+DOWN" = "cycle audio down";

        y = "add audio-delay 0.010";
        o = "add audio-delay -0.010";

        i = ''cycle-values vf "sub,lavfi=negate" ""'';
        S = "playlist-shuffle";

        a = "ab-loop";

        "Alt+r" = "playlist-shuffle";
      };
      scripts = with pkgs.mpvScripts; [
        # Load all files in directory to playlist, playing next alphabetically ordered file on playback end.
        autoload
        # Better UI
        uosc
        # Allows media playback buttons to work in mpv
        mpris
        # Thumbnail support, needs uosc to work
        thumbfast
        # Prevents screen sleep on gnome
        inhibit-gnome
      ];
      config = {
        vo = cfg.vo;
        alang = ["jpn" "eng"];
        slang = ["eng"];

        autofit = "100%";
        geometry = "40%x40%";
        window-maximized = "yes";
      };
      profiles = {
        "extension.gif" = {
          cache = "no";
          no-pause = "";
          loop-file = "yes";
        };
        "extension.webm" = {
          no-pause = "";
          loop-file = "yes";
        };
      };
    };
  };
}

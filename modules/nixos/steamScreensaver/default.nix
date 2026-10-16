{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.steamScreensaver;
  owner = config.kirk.steamShortcuts.user;
  group = config.users.users.${owner}.group;
  uioverrides = "${config.kirk.steamShortcuts.steamRoot}/config/uioverrides";
  dir = "${uioverrides}/screensavers/video";
in {
  options.kirk.steamScreensaver = {
    enable = mkEnableOption "a Steam Big Picture screensaver that loops a video";

    video = mkOption {
      type = types.str;
      example = "/data/.state/steam/screensaver.mp4";
      description = "Absolute path of the video, copied into Steam's directory once, because Steam's web helper only reads files inside Steam's directory and the store. Delete the copy to replace the video.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${uioverrides}              0755 ${owner} ${group} -"
      "d ${uioverrides}/screensavers 0755 ${owner} ${group} -"
      "d ${dir}                      0755 ${owner} ${group} -"
      "L+ ${dir}/index.html - - - - ${./index.html}"
      "L+ ${dir}/main.css   - - - - ${./main.css}"
      "C ${dir}/video.mp4   - - - - ${cfg.video}"
    ];
  };
}

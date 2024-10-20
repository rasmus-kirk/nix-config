{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.xdgMime;
in {
  options.kirk.xdgMime = {
    enable = mkEnableOption "xdg-mime associations. Warning, this depends on various other submodules from this root module";
  };

  config = mkIf cfg.enable {
    xdg.desktopEntries = with pkgs.lib; {
      pdf = {
        name = "Zathura";
        exec = "${getExe pkgs.zathura} %U";
      };
      audio = {
        name = "Audio Player - MPV";
        exec = "${getExe pkgs.mpv} --force-window %u";
      };
      image = {
        name = "Image Viewer - MPV";
        exec = "${getExe config.kirk.mvi.package} %u";
      };
      video = {
        name = "Media Player - MPV";
        exec = "${getExe pkgs.mpv} %u";
      };
      yazi = {
        name = "Yazi";
        exec = "${getExe pkgs.foot} ${getExe pkgs.yazi} %u";
        #mimeType = [ "inode/directory" ];
      };
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        # Audio
        "application/octet-stream" = [ "audio.desktop" ];
        "audio/flac" = [ "audio.desktop" ];
        "audio/mpeg" = [ "audio.desktop" ];
        "audio/x-vorbis+ogg" = [ "audio.desktop" ];

        # Image
        "image/jpeg" = [ "image.desktop" ];
        "image/png" = [ "image.desktop" ];
        "image/webp" = [ "image.desktop" ];

        # Video
        "image/gif" = [ "video.desktop" ];
        "video/mp4" = [ "video.desktop" ];
        "video/x-matroska" = [ "video.desktop" ];

        # PDF
        "application/pdf" = [ "pdf.desktop" ];

        # File Manager
        "inode/directory" = [ "yazi.desktop" ];

        # Browser
        "x-scheme-handler/about" = [ "librewolf.desktop" ];
        "x-scheme-handler/http" = [ "librewolf.desktop" ];
        "x-scheme-handler/https" = [ "librewolf.desktop" ];
        "x-scheme-handler/unknown" = [ "librewolf.desktop" ];
      };
    };
  };
}

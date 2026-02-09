{
  config,
  pkgs,
  lib,
  ...
}: with lib; {
  options.kirk.userDirs = {
    enable = mkEnableOption "userDirs";

    rootDir = mkOption {
      type = types.path;
      default = config.home.homeDirectory;
      example = "/data";
      description = "The root path to put all the XDG user directories.";
    };

    autoSortDownloads = mkOption {
      type = types.bool;
      default = true;
      description = "Whether or not to auto-sort downloads.";
    };
  };
  config = let
    cfg = config.kirk.userDirs;
    sort-downloads = pkgs.writeShellApplication {
      name = "sort-downloads";
      runtimeInputs = with pkgs; [toybox];
      text = ''
        downRoot="${config.xdg.userDirs.extraConfig.XDG_DOWNLOADS_ROOT}"
        unsorted="${config.xdg.userDirs.download}"

        mkdir -p $downRoot/documents
        mkdir -p $downRoot/archives
        mkdir -p $downRoot/audio
        mkdir -p $downRoot/videos
        mkdir -p $downRoot/images
        mkdir -p $downRoot/text

        cd $unsorted

        mv -vn ./*.pdf                                           \
               $downRoot/documents ||:

        mv -vn ./*.zip   ./*.rar                                 \
           $downRoot/archives ||:

        mv -vn ./*.flac  ./*.m4a    ./*.mp3   ./*.flac   ./*.ogg \
           ./*.wav                                           \
           $downRoot/audio ||:

        mv -vn ./*.avi   ./*.av1    ./*.flv   ./*.mkv    ./*.m4v \
           ./*.mov   ./*.mp4    ./*.ts    ./*.webm   ./*.wmv \
           $downRoot/videos ||:

        mv -vn ./*.avif  ./*.bmp    ./*.gif   ./*.heic   ./*.jpe \
           ./*.jpeg  ./*.jpg    ./*.pgm   ./*.png    ./*.ppm \
           ./*.webp                                          \
           $downRoot/images ||:

        mv -vn ./*.build ./*.c      ./*.cmake ./*.conf   ./*.cpp \
           ./*.css   ./*.csv    ./*.cu    ./*.ebuild ./*.eex \
           ./*.env   ./*.ex     ./*.exs   ./*.go     ./*.h   \
           ./*.java  ./*.hs     ./*.html  ./*.ini    ./*.hpp \
           ./*.json  ./*.js     ./*.kt    ./*.lua    ./*.log \
           ./*.micro ./*.md     ./*.micro ./*.ninja  ./*.nix \
           ./*.py    ./*.rkt    ./*.rs    ./*.scss   ./*.sh  \
           ./*.srt   ./*.svelte ./*.toml  ./*.tsx    ./*.txt \
           ./*.vim   ./*.xml    ./*.yaml  ./*.yml            \
           $downRoot/text ||:
      '';
    };
  in mkIf cfg.enable {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;

      extraConfig.XDG_DOWNLOADS_ROOT = "${cfg.rootDir}/downloads";
      desktop = "${cfg.rootDir}";
      documents = "${cfg.rootDir}/media/documents";
      download = "${config.xdg.userDirs.extraConfig.XDG_DOWNLOADS_ROOT}/unsorted";
      music = "${cfg.rootDir}/media/audio/music";
      pictures = "${cfg.rootDir}/media/images";
      # publicShare = "${cfg.rootDir}/.public";
      # templates = "${cfg.rootDir}/.templates";
      videos = "${cfg.rootDir}/media/videos";
    };

    systemd.user = mkIf cfg.autoSortDownloads {
      timers = {
        autoSortDownloads = {
          Unit.Description = "Auto sorts downloads by download type";

          Timer = {
            OnCalendar = "daily";
            Persistent = "true"; # Run service immediately if last window was missed
            RandomizedDelaySec = "1h"; # Run service OnCalendar +- 1h
          };

          Install.WantedBy = ["timers.target"];
        };
      };

      services = {
        autoSortDownloads = {
          Unit.Description = "Auto sorts downloads by download type";

          Service = {
            ExecStart = "${sort-downloads}/bin/sort-downloads";
            Type = "oneshot";
          };
        };
      };
    };
  };
}

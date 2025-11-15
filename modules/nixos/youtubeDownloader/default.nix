{ config, pkgs, lib, ... }:
with lib;

let
  cfg = config.kirk.youtubeDownloader;

  channelsFile = pkgs.writeText "channels.txt" (concatStringsSep "\n" cfg.channels);

  downloadChannelScript = pkgs.writeShellApplication {
    name = "download-channel-script";
    runtimeInputs = with pkgs; [ yt-dlp ];
    text = ''
      # TheFrenchGhosty's Ultimate YouTube-DL Scripts Collection
      # Cleaned and customized to download full channels at 1080p, preferring AV1 > VP9 > AVC1
      # https://github.com/TheFrenchGhosty/TheFrenchGhostys-Ultimate-YouTube-DL-Scripts-Collection

      yt-dlp \
        --format "bv[height<=1080][vcodec^=av01]+ba/bv[height<=1080][vcodec^=vp9]+ba/bv[height<=1080][vcodec^=avc1]+ba/b[height<=1080]" \
        --merge-output-format "mkv" \
        --output "${cfg.outputDir}/%(uploader)s/All Videos/%(upload_date)s - %(title)s [%(id)s]/%(upload_date)s - %(title)s [%(id)s].%(ext)s" \
        --download-archive "${cfg.outputDir}/archive.log" \
        --no-continue \
        --no-overwrites \
        --force-ipv4 \
        --sleep-requests 1 \
        --sleep-interval 5 \
        --max-sleep-interval 30 \
        --ignore-errors \
        --add-metadata \
        --parse-metadata "%(title)s:%(meta_title)s" \
        --parse-metadata "%(uploader)s:%(meta_artist)s" \
        --write-description \
        --write-info-json \
        --write-annotations \
        --write-thumbnail \
        --embed-thumbnail \
        --sponsorblock-mark all \
        --sponsorblock-remove sponsor \
        --write-subs \
        --write-auto-subs \
        --sub-lang "en.*,ja,da" \
        --embed-subs \
        --check-formats \
        --concurrent-fragments 3 \
        --match-filter "!is_live & !live" \
        --throttled-rate 100K \
        --batch-file ${channelsFile} \
        --verbose
    '';
  };
in {
  options.kirk.youtubeDownloader = {
    enable = mkEnableOption "Enable the YouTube downloader service.";

    channels = mkOption {
      type = with types; listOf types.str;
      default = [];
      description = "List of YouTube channel URLs to download.";
    };

    outputDir = mkOption {
      type = types.str;
      default = "/var/lib/ytdl";
      description = "Absolute path to directory where downloaded videos will be stored.";
    };

    user = mkOption {
      type = types.str;
      default = "ytdl";
      description = "System user to run the downloader service as.";
    };

    group = mkOption {
      type = types.str;
      default = "ytdl";
      description = "Group ownership for the output directory and service.";
    };

    timerInterval = mkOption {
      type = types.str;
      default = "daily";
      description = ''
        systemd timer OnCalendar value, e.g. "daily", "hourly", "weekly", "Mon *-*-* 12:00:00"
        Defines how often the download runs automatically.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users = {
      # Create the user if it doesn't exist
      # Note: system user, no login shell
      # If you want custom UID/GID, user can override with user/group options
      ${cfg.user} = mkIf (cfg.user == "ytdl") {
        isSystemUser = true;
        description = "User for running YouTube downloader service";
        group = cfg.group;
        home = cfg.outputDir;
        createHome = false;
      };
    };
    users.groups.${cfg.group} = mkIf (cfg.group == "ytdl") {};

    environment.systemPackages = with pkgs; [
      yt-dlp
    ];

    systemd.tmpfiles.rules = [
      # Create output dir with proper ownership & perms
      "d ${cfg.outputDir} 0775 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.youtubeDownloader = {
      description = "YouTube Channel Downloader Service";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        UMask = "002";
        ExecStart = "${pkgs.lib.getExe downloadChannelScript}";
        Restart = "on-failure";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.outputDir;
      };

      wantedBy = [ "multi-user.target" ];
    };
    systemd.timers.youtubeDownloader = {
      description = "Timer to run YouTube downloader service";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}


{ config, pkgs, lib, ... }:

with lib;

let
	cfg = config.kirk.userDirs;

	sort-downloads = pkgs.writeShellApplication {
		name = "sort-downloads";

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
			   $downRoot/video ||:

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
in {
	options.kirk.userDirs= {
		enable = mkEnableOption "userDirs";

		autoSortDownloads = mkOption {
			type = types.bool;
			default = true;

			description = ''
				Whether or not to auto-sort downloads.
			'';
		};
	};

	config = mkIf cfg.enable {
		xdg.userDirs = {
			enable = true;
			createDirectories = true;

			extraConfig.XDG_DOWNLOADS_ROOT = "${config.home.homeDirectory}/downloads";

			desktop = "${config.home.homeDirectory}/desktop";
			documents = "${config.home.homeDirectory}/documents";
			download = "${config.xdg.userDirs.extraConfig.XDG_DOWNLOADS_ROOT}/unsorted";
			music = "${config.home.homeDirectory}/music";
			pictures = "${config.home.homeDirectory}/pictures";
			publicShare = "${config.home.homeDirectory}/public";
			templates = "${config.home.homeDirectory}/templates";
			videos = "${config.home.homeDirectory}/videos";
		};

		systemd.user = mkIf cfg.autoSortDownloads {
			timers = {
				autoSortDownloads = {
					Unit.Description = "Auto sorts downloads by download type";

					Timer = {
						OnCalendar="daily";
						Persistent="true"; # Run service immediately if last window was missed
						RandomizedDelaySec="1h"; # Run service OnCalendar +- 1h
					};

					Install.WantedBy=["timers.target"];
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

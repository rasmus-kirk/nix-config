{ config, pkgs, lib, ... }:

with lib;

let
	cfg = config.kirk.jiten;

	word-of-the-day = pkgs.writeShellApplication {
		name = "word-of-the-day";

		runtimeInputs = with pkgs; [ jiten ];
		
		text = ''
			path=${config.xdg.stateHome}/word-of-the-day
			mkdir -p $path
			if ! [ "$(cat $path/last-update.txt)" = "$(date +"%Y-%m-%d")" ]; then
				jiten --colour -v jmdict --romaji -n 1 +random | tail -n +3 > $path/japanese.txt
				echo "" >> $path/japanese.txt
				date +"%Y-%m-%d" > $path/last-update.txt
			fi
		'';
		}; 
in {
	options.kirk.jiten = {
		enable = mkEnableOption "jiten japanese dictionary";

		dailyWord = mkOption {
			type = types.bool;
			default = true;
			description = ''
				Enable daily japanese word prompt.
			'';
		};
	};

	config = mkIf cfg.enable {
		home.packages = with pkgs; [ jiten ];

		programs.zsh.initExtra  = mkIf cfg.dailyWord "cat ${config.xdg.stateHome}/word-of-the-day/japanese.txt";
		programs.bash.initExtra = mkIf cfg.dailyWord "cat ${config.xdg.stateHome}/word-of-the-day/japanese.txt";

		systemd.user = mkIf cfg.dailyWord {
			timers = {
				word-of-the-day = {
					Unit.Description = "Gets a japanese word from the Jiten dictionary";

					Timer = {
						OnCalendar="daily";
						Persistent="true";
						RandomizedDelaySec="1h";
					};

					Install.WantedBy=["timers.target"];
				};
			};

			services = {
				word-of-the-day = {
					Unit.Description = "Updates the daily japanese word";

					Service = {
						ExecStart = "${word-of-the-day}";
						Type = "oneshot";
					};
				};
			};
		};
	};
}

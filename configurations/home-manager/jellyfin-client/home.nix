{pkgs, lib, ...}: let
  configDir = "/data/.system-configuration";
  machine = "jellyfin-client";
  username = "user";

  timeout = 15;
  timer = 3;
  logLength = timeout / timer;
in {
  kirk = {
    foot.enable = true;
    terminalTools.enable = true;
    git = {
      enable = true;
      userEmail = "mail@rasmuskirk.com";
      userName = "rasmus-kirk";
    };
    helix = {
      enable = true;
      installMostLsps = false;
      extraPackages = with pkgs; [nil marksman nodePackages_latest.bash-language-server];
    };
    homeManagerScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
    userDirs.enable = true;
    yazi = {
      enable = true;
      configDir = configDir;
    };
    zsh.enable = true;
    fonts.enable = true;
  };

  wayland.windowManager.sway = {
    enable = true;
    config = let 
      mod = "Mod4";
      left = "h";
      down = "j";
      up = "k";
      right = "l";
      jellyfinLog = pkgs.writeShellScriptBin "start-jellyfin" ''
        log_dir="$HOME/.local/share/start-jellyfin"

        # Make sure $log_file exists
        mkdir -p "$log_dir"
        touch "$log_dir/log"

        ${lib.getExe pkgs.jellyfin-media-player} > "$log_dir/log" 2>&1
      '';
      startJellyfin = pkgs.writeShellScriptBin "start-jellyfin" ''
        sleep 3
        exec swaymsg 'workspace main; exec ${lib.getExe jellyfinLog}'
        #exec swaymsg 'workspace main; exec ${lib.getExe pkgs.jellyfin-media-player} --tv'

        #${lib.getExe pkgs.jellyfin-media-player} --tv > "$log_dir/log" 2>&1
        #exec swaymsg 'workspace main; exec ${lib.getExe pkgs.jellyfin-media-player} --tv' > "$log_dir/sway" 2>&1
        #exec swaymsg 'workspace main; exec ${lib.getExe pkgs.jellyfin-media-player} --tv > "$log_dir/jellyfin" 2>&1' > "$log_dir/sway" 2>&1
        #${lib.getExe pkgs.jellyfin-media-player} --tv > "$log_dir/jellyfin" 2>&1
      '';
    in {
      modifier = mod;
      bars = [];
      startup = [ {
        command = "swaymsg 'workspace main; exec ${lib.getExe startJellyfin}'";
        #command = "swaymsg 'workspace main; exec ${lib.getExe pkgs.jellyfin-media-player} --tv'";
      } ];
      # Remove window borders
      window.border = 0;
      # Hide cursor after 1 second
      seat."*".hide_cursor = "1000";
      # Set keyboard settings
      input."*" = {
        repeat_delay = "300";
        repeat_rate = "50";
      };
      # Set background to jellyfin logo
      output."*".bg = "${./wallpaper.png} fill";
      # Standard keybindings
      keybindings = with pkgs.lib; {
        "${mod}+Space" = "exec ${getExe pkgs.foot}";
        "${mod}+Return" = "exec ${getExe pkgs.foot}";
        "${mod}+w" = "exec ${getExe pkgs.librewolf}";
        "${mod}+e" = "exec ${getExe pkgs.jellyfin-media-player}";
        "${mod}+q" = "kill";
        "${mod}+f" = "fullscreen";

        # Move your focus around
        "${mod}+${left}" = "focus left";
        "${mod}+${down}" = "focus down";
        "${mod}+${up}" = "focus up";
        "${mod}+${right}" = "focus right";
        "${mod}+Left" = "focus left";
        "${mod}+Down" = "focus down";
        "${mod}+Up" = "focus up";
        "${mod}+Right" = "focus right";

        # Move the focused window with the same, but add Shift
        "${mod}+Shift+${left}" = "move left";
        "${mod}+Shift+${down}" = "move down";
        "${mod}+Shift+${up}" = "move up";
        "${mod}+Shift+${right}" = "move right";
        "${mod}+Shift+Left" = "move left";
        "${mod}+Shift+Down" = "move down";
        "${mod}+Shift+Up" = "move up";
        "${mod}+Shift+Right" = "move right";

        # Switch to workspace
        "${mod}+1" = "workspace number 1";
        "${mod}+2" = "workspace number 2";
        "${mod}+3" = "workspace number 3";
        "${mod}+4" = "workspace number 4";
        "${mod}+5" = "workspace number 5";
        "${mod}+6" = "workspace number 6";
        "${mod}+7" = "workspace number 7";
        "${mod}+8" = "workspace number 8";
        "${mod}+9" = "workspace number 9";
        "${mod}+0" = "workspace number 10";

        # Move focused container to workspace
        "${mod}+Shift+1" = "move container to workspace number 1";
        "${mod}+Shift+2" = "move container to workspace number 2";
        "${mod}+Shift+3" = "move container to workspace number 3";
        "${mod}+Shift+4" = "move container to workspace number 4";
        "${mod}+Shift+5" = "move container to workspace number 5";
        "${mod}+Shift+6" = "move container to workspace number 6";
        "${mod}+Shift+7" = "move container to workspace number 7";
        "${mod}+Shift+8" = "move container to workspace number 8";
        "${mod}+Shift+9" = "move container to workspace number 9";
        "${mod}+Shift+0" = "move container to workspace number 10";

        # Special keys to adjust volume via PulseAudio
        "XF86AudioMute" = ''exec pactl set-sink-mute \@DEFAULT_SINK@ toggle'';
        "XF86AudioLowerVolume" = ''exec pactl set-sink-volume \@DEFAULT_SINK@ -5%'';
        "XF86AudioRaiseVolume" = ''exec pactl set-sink-volume \@DEFAULT_SINK@ +5%'';
        "XF86AudioMicMute" = ''exec pactl set-source-mute \@DEFAULT_SOURCE@ toggle'';

        # Special keys to adjust brightness via brightnessctl
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
      };
    };
  };

  # Autoconnect HDMI
  services.kanshi = {
    enable = true;
    profiles = {
      undocked.outputs = [ {
        criteria = "eDP-1";
        status = "enable";
      } ];
      docked.outputs = [ {
        criteria = "eDP-1";
        status = "disable";
      } {
        criteria = "*";
        status = "enable";
      } ];
    };
  };

  # Start sway on system startup
  programs.zsh.initExtra = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_VTNR" ] && [ "$XDG_VTNR" -eq 1 ] ; then
        exec sway
    fi
  '';

  services.swayidle = {
    enable = true;
    timeouts = let
      checkSoundScript = pkgs.writeShellApplication {
        name = "check-sound";
        runtimeInputs = with pkgs; [ coreutils gawk systemd ];
        text = ''
          # TODO: Option or global here
          log_file="$HOME/.local/cache/soundOutput/log"

          self_log_dir="$HOME/.local/share/swayidle-custom"

          # Make sure $log_file exists
          mkdir -p "$self_log_dir"
          touch "$self_log_dir/log"

          sum=$(awk '{s+=$1} END {print s}' "$log_file")
          if [ "$sum" -eq "0" ]; then
            systemctl suspend
          fi
        '';
      };
    in [ {
      timeout = timeout * 60;
      command = lib.getExe checkSoundScript;
    } ];
  };

  systemd.user = {
    #timers = {
    #  logSound = {
    #    Unit.Description = "Timer for logSound";

    #    Timer = {
    #      OnBootSec = "0";
    #      OnUnitActiveSec = "${builtins.toString timer} min";
    #      Persistent = "true"; # Run service immediately if last window was missed
    #    };

    #    Install.WantedBy = ["timers.target"];
    #  };
    #};

    services = let 
      logSoundScript = pkgs.writeShellApplication {
        name = "log-sound";
        runtimeInputs = with pkgs; [ coreutils gnugrep pipewire ];
        text = ''
          log_file="$HOME/.local/cache/soundOutput/log"
          log_file_test="$HOME/.local/cache/soundOutput/log_test"

          # Make sure $log_file exists
          mkdir -p "$(dirname "$log_file")"
          touch "$log_file"

          # Get current current number of playing streams
          #current_playing=$(pw-dump | grep running -c || true)
          current_playing=$(pactl list sink-inputs | grep -c "Corked: no" || true)
          pactl list sink-inputs > "$log_file_test"
          log_len=$(wc -l < "$log_file")
          echo "Current playing streams $current_playing"

          # Log the current number of playing streams
          #echo "$current_playing" >> "$log_file"
          echo 1 >> "$log_file"

          # If we have more than $timeout entries in log,
          # we remove an entry
          echo "Log length: $log_len / ${builtins.toString logLength}"
          if [ "$log_len" -ge "${builtins.toString logLength}" ]; then
            echo "Removing the first line of $log_file"
            tmp=$(mktemp)
            tail -n +2 "$log_file" > "$tmp"
            cat "$tmp" > "$log_file"
          fi
        '';
      };
    in {
      logSound = {
        Unit.Description = "Logs current sound level.";

        Service = {
          ExecStart = lib.getExe logSoundScript;
          #Type = "oneshot";
          Restart = "always";
          RestartSec = "${builtins.toString timer} min";
        };
      };
    };
  };

  # TODO: Add to kirk-module
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
    ];
    config = {
      # TODO: wtf is the reason for this? It should not be necessary. WHY DOES IT WORK!?
      #vo = "x11";

      alang = ["jpn" "eng"];
      slang = ["eng"];
      #extension.gif = {
      #  cache = "no";
      #  no-pause = "";
      #  loop-file = "yes";
      #};
      #extension.webm = {
      #  no-pause = "";
      #  loop-file = "yes";
      #};
    };
  };

  home.packages = with pkgs; [
    pulsemixer
    jellyfin-media-player
    librewolf
    foot
    wl-clipboard
    pulseaudio
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

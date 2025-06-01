{
  pkgs,
  lib,
  ...
}: let
  configDir = "/data/.system-configuration";
  secretDir = "/data/.secret";
  machine = "server";
  username = "user";
in {
  kirk = {
    foot.enable = true;
    terminalTools.enable = true;
    ssh = {
      enable = true;
      identityPath = "${secretDir}/server/ssh/id_ed25519";
    };
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
      startJellyfin = pkgs.writeShellScriptBin "start-jellyfin" ''
        sleep 3
        ${lib.getExe pkgs.jellyfin-media-player}
      '';
    in {
      modifier = mod;
      bars = [];
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
      startup = [
        {
          command = "workspace 1; exec ${lib.getExe startJellyfin}";
        }
      ];

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
        # "XF86AudioLowerVolume" = ''exec pactl set-sink-volume \@DEFAULT_SINK@ -5%'';
        # "XF86AudioRaiseVolume" = ''exec pactl set-sink-volume \@DEFAULT_SINK@ +5%'';
        # "XF86AudioMicMute" = ''exec pactl set-source-mute \@DEFAULT_SOURCE@ toggle'';

        "XF86Sleep" = "${getExe pkgs.jellyfin-media-player}";
        # Special keys to adjust brightness via brightnessctl
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
      };
    };
  };

  # Autoconnect HDMI
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "undocked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
        ];
      }
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "*";
            status = "enable";
          }
        ];
      }
    ];
  };

  # Start sway on system startup
  programs.zsh.initContent = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_VTNR" ] && [ "$XDG_VTNR" -eq 1 ] ; then
        exec sway
    fi
  '';

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

# The desktop's graphical seat: Jovian game mode + the Plasma desktop.
# Persistence (state dirs and the links into this home) is done with system
# tmpfiles in configurations/nixos/desktop/configuration.nix.
{...}: let
  username = "steam";
in {
  kirk = {
    foot.enable = true;
    fonts.enable = true;
    mpv.enable = true;
    xdgMime.enable = true;
    cec = {
      enable = true;
      sink = "alsa_output.pci-0000_03_00.1.hdmi-stereo"; # the LG TV (Navi 48 HDMI; node.nick "LG TV")
      keepAwake.debug = true; # TEMP: verify monitor RMS in the journal
      controllerVolume.enable = true;
    };
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "22.11";

  home.shellAliases.restart-steam = "systemctl --user restart steam-launcher.service";
}

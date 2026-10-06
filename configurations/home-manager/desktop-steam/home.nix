# The desktop's graphical seat: Jovian game mode.
# Persistence (state dirs and the links into this home) is done with system
# tmpfiles in configurations/nixos/desktop/configuration.nix.
{...}: let
  username = "steam";
in {
  kirk = {
    terminalTools.enable = true;
    foot.enable = true;
    helix.enable = true;
    scripts.enable = true;
    yazi.enable = true;
    zsh.enable = true;
    fonts.enable = true;
    mpv.enable = true;
    mvi.enable = true;
    zathura = {
      enable = true;
      darkmode = false;
    };
  };

  programs.bash = {
    enable = true;
    initExtra = "exec zsh";
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "22.11";
}

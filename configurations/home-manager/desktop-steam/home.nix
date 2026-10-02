# The desktop's graphical seat: Jovian game mode.
# Persistence (state dirs and the links into this home) is done with system
# tmpfiles in configurations/nixos/desktop/configuration.nix.
{...}: let
  username = "steam";
in {
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "22.11";
}

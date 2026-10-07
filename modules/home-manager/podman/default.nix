{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.podman;
  podman = config.services.podman.package;
in {
  options.kirk.podman = {
    enable =
      mkEnableOption "rootless podman with docker-compose and a user podman socket"
      // {
        description = ''
          Rootless podman with a Docker-compatible API socket, so
          `docker-compose` and other Docker clients work through `DOCKER_HOST`.

          This module links the user units shipped by the podman package
          into `~/.config/systemd/user` and enables `podman.socket` through
          `sockets.target`. Home-manager's `services.podman` provides the
          package but no API socket. The shipped service sets `Delegate=true`
          and `KillMode=process`, so containers keep running when the API
          service stops.
        '';
      };
  };

  config = mkIf cfg.enable {
    services.podman.enable = true;

    home.packages = [pkgs.docker-compose];

    home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/podman/podman.sock";

    xdg.configFile = {
      "systemd/user/podman.socket".source = "${podman}/share/systemd/user/podman.socket";
      "systemd/user/podman.service".source = "${podman}/share/systemd/user/podman.service";
      "systemd/user/sockets.target.wants/podman.socket".source = "${podman}/share/systemd/user/podman.socket";
    };
  };
}

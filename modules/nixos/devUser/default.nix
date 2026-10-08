{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.devUser;
in {
  options.kirk.devUser = {
    enable = mkEnableOption "isolated development user";
    user = mkOption {
      type = types.str;
      default = "user";
      description = "Existing user that gets sudo access to dev and membership in the dev group.";
    };
  };

  config = mkIf cfg.enable {
    kirk.yubikey.hidrawGroup = true;

    users.groups.dev = {};

    users.users.dev = {
      isNormalUser = true;
      description = "Isolated development user";
      group = "dev";
      # Group yubikey gives access to the FIDO hidraw device for the sk key.
      extraGroups = ["yubikey"];
      # Password login is disabled. Access goes through sudo from the main user.
      hashedPassword = "!";
      # Keeps dev's user manager running when no session is open.
      linger = true;
      homeMode = "750";
    };

    users.users.${cfg.user}.extraGroups = ["dev"];

    environment.extraInit = ''
      if [ -z "$XDG_RUNTIME_DIR" ] && [ -d "/run/user/$(id -u)" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      fi
    '';

    # `screenshot` copies captures here, since dev cannot read /data.
    # Root creates the directory at boot, which reserves the name in sticky /tmp.
    # The missing age field exempts it from tmpfiles cleanup.
    systemd.tmpfiles.rules = [
      "d /tmp/screenshots 0750 ${cfg.user} dev -"
    ];

    # runAs limits the target user to dev.
    security.sudo.extraRules = [
      {
        users = [cfg.user];
        runAs = "dev";
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };
}

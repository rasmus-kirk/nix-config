{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.devUser;
in {
  options.kirk.devUser.enable = mkEnableOption "isolated development user";

  config = mkIf cfg.enable {
    users.groups.dev = {};

    users.users.dev = {
      isNormalUser = true;
      description = "Isolated development user";
      group = "dev";
      # yubikey grants the FIDO hidraw needed to use the sk key.
      extraGroups = ["yubikey"];
      # Locked: the only way in is sudo from user.
      hashedPassword = "!";
      # `sudo -i` creates no logind session, so user timers need lingering.
      linger = true;
    };

    # `screenshot` mirrors captures here because dev cannot read /data. Root creates it at boot so
    # no other uid can claim the name in sticky /tmp. No age field, so tmpfiles cleanup skips it.
    systemd.tmpfiles.rules = [
      "d /tmp/screenshots 0750 user dev -"
    ];

    # runAs pins the target: grants dev, never root.
    security.sudo.extraRules = [
      {
        users = ["user"];
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

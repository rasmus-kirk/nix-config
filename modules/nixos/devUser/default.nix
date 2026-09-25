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

    # Screenshot hand-off drop. `screenshot` (kirk.scripts) archives captures
    # under /data, which is 0700 user:users and so invisible to dev; it also
    # mirrors each one here, and dev's box bind-mounts this path read-only so
    # Claude can be shown images. Root creates it at boot: owner user writes,
    # group dev reads, nobody else sees it — and pre-creating it here means
    # another uid can't win the race for the name in sticky /tmp. No age
    # argument, so systemd-tmpfiles' /tmp cleanup leaves the directory alone.
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

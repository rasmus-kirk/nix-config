{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.yubikey;
in {
  options.kirk.yubikey = {
    enable = mkEnableOption "YubiKey login, sudo and greeter authentication";

    authfile = mkOption {
      type = types.str;
      default = "/data/.secret/ssh/id_ed25519_yubi";
      description = "Resident SSH key handle that pam_u2f authenticates against.";
    };

    origin = mkOption {
      type = types.str;
      default = "ssh:rasmus";
      description = "Application string the SSH key was created with.";
    };

    lockOnUnplug = mkOption {
      type = types.bool;
      default = false;
      description = "Lock all sessions when a YubiKey is unplugged.";
    };

    lockOnlyWithDevices = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["17ef:6047"];
      description = "USB vendor:product IDs. If set, unplugging only locks while one of these devices is connected.";
    };

    sshAgent = mkOption {
      type = types.bool;
      default = false;
      description = "Run the OpenSSH agent instead of gcr's, with terminal prompts for key touches.";
    };

    hidrawGroup = mkOption {
      type = types.bool;
      default = false;
      description = "Give the yubikey group access to the YubiKey FIDO node, in addition to the seat user.";
    };
  };

  config = mkIf cfg.enable {
    security.pam.services = {
      login.u2fAuth = true;
      sudo.u2fAuth = true;
      sddm.u2fAuth = mkIf config.services.displayManager.sddm.enable true;
      kde.u2fAuth = mkIf config.services.desktopManager.plasma6.enable true;
      cosmic-greeter = mkIf config.services.displayManager.cosmic-greeter.enable {
        u2fAuth = true;
        unixAuth = false;
      };
    };

    security.pam.u2f.settings = {
      cue = true;
      authfile = cfg.authfile;
      sshformat = true;
      origin = cfg.origin;
    };

    programs.ssh = mkIf cfg.sshAgent {
      startAgent = true;
      askPassword = "";
    };
    environment.variables.SSH_ASKPASS = mkIf cfg.sshAgent "";
    services.gnome = mkIf cfg.sshAgent {
      gnome-keyring.enable = false;
      gcr-ssh-agent.enable = false;
    };

    users.groups.yubikey = mkIf cfg.hidrawGroup {};

    services.udev.extraRules =
      optionalString cfg.hidrawGroup ''
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", GROUP="yubikey", MODE="0660"
      ''
      + optionalString cfg.lockOnUnplug ''
        ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.writeShellScript "yubikey-lock-on-unplug" (
          if cfg.lockOnlyWithDevices == []
          then "${pkgs.systemd}/bin/loginctl lock-sessions"
          else ''
            for id in ${escapeShellArgs cfg.lockOnlyWithDevices}; do
              if ${pkgs.usbutils}/bin/lsusb -d "$id" > /dev/null; then
                exec ${pkgs.systemd}/bin/loginctl lock-sessions
              fi
            done
          ''
        )}"
      '';

    environment.systemPackages = [pkgs.yubioath-flutter];
  };
}

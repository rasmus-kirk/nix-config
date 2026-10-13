{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeAssistant;
in {
  options.kirk.homeAssistant = {
    enable = mkEnableOption "Home Assistant with ZHA and the IKEA STYRBAR remotes";

    stateDir = mkOption {
      type = types.str;
      description = "Home Assistant state directory.";
    };

    hassGroupMembers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users added to the hass group, with read access to the state directory.";
    };
  };

  config = mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      configDir = cfg.stateDir;
      extraComponents = [
        "analytics"
        "google_translate"
        "met"
        "radio_browser"
        "shopping_list"
        "zha"
        "usb"
        "isal"
      ];
      configWritable = true;
      blueprints.automation = [./ikea-styrbar.yaml];
      config = {
        default_config = {};
        "automation ui" = "!include automations.yaml";
        "automation nixos" = import ./automations.nix;
      };
    };

    systemd.services.home-assistant.serviceConfig.UMask = mkForce "0027";
    users.users =
      {hass.homeMode = "750";}
      // genAttrs cfg.hassGroupMembers (_: {extraGroups = ["hass"];});

    networking.firewall.allowedTCPPorts = [8123];
  };
}

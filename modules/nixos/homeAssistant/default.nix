{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeAssistant;

  sensors = deviceClass: "states.sensor | selectattr('attributes.device_class', 'defined') | selectattr('attributes.device_class', 'eq', '${deviceClass}') | rejectattr('entity_id', 'in', integration_entities('mobile_app')) | selectattr('state', 'is_number') | list";

  climateClasses = [
    {
      heading = "Temperature";
      class = "temperature";
      unit = "°C";
    }
    {
      heading = "Humidity";
      class = "humidity";
      unit = "%";
    }
    {
      heading = "CO2";
      class = "carbon_dioxide";
      unit = "ppm";
    }
    {
      heading = "PM2.5";
      class = "pm25";
      unit = "µg/m³";
    }
  ];

  averageSensor = {class, unit, ...}: {
    name = "Average ${class}";
    unique_id = "average_${class}";
    unit_of_measurement = unit;
    state_class = "measurement";
    availability = "{{ ${sensors class} | count > 0 }}";
    state = "{{ (${sensors class} | map(attribute='state') | map('float') | average) | round(1) }}";
  };

  climateSection = {heading, class, ...}: {
    type = "grid";
    cards = [
      {
        type = "heading";
        inherit heading;
      }
      {
        type = "history-graph";
        hours_to_show = 24;
        entities = [
          {
            entity = "sensor.average_${class}";
            name = "Average";
          }
        ];
      }
      {
        type = "custom:auto-entities";
        card_param = "cards";
        card = {
          type = "grid";
          columns = 1;
          square = false;
        };
        filter = {
          include = [
            {
              domain = "sensor";
              attributes.device_class = class;
              options = {
                type = "history-graph";
                hours_to_show = 24;
                entities = ["this.entity_id"];
              };
            }
          ];
          exclude = [{integration = "mobile_app";}];
        };
      }
    ];
  };

  climateDashboard = pkgs.writeText "climate.yaml" (builtins.toJSON {
    views = [
      {
        title = "Climate";
        type = "sections";
        sections = map climateSection climateClasses;
      }
    ];
  });
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

    thread = {
      enable = mkEnableOption "a Thread border router and Matter controller for Home Assistant";

      radioDevice = mkOption {
        type = types.str;
        description = "/dev/serial/by-id path of the stick with OpenThread RCP firmware.";
      };

      backboneInterface = mkOption {
        type = types.str;
        description = "LAN interface that routes between the Thread mesh and the network.";
      };
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
      ] ++ optionals cfg.thread.enable ["thread" "otbr" "matter"];
      configWritable = true;
      blueprints.automation = [./ikea-styrbar.yaml];
      customLovelaceModules = [pkgs.home-assistant-custom-lovelace-modules.auto-entities];
      config = {
        default_config = {};
        "automation ui" = "!include automations.yaml";
        "automation nixos" = import ./automations.nix {inherit sensors;};
        template = [{sensor = map averageSensor climateClasses;}];
        lovelace.dashboards.climate-dashboard = {
          mode = "yaml";
          filename = "climate.yaml";
          title = "Climate";
          icon = "mdi:home-thermometer";
          show_in_sidebar = true;
        };
      };
    };

    systemd.tmpfiles.rules = ["L+ ${cfg.stateDir}/climate.yaml - - - - ${climateDashboard}"];

    systemd.services.home-assistant.serviceConfig.UMask = mkForce "0027";
    users.users =
      {hass.homeMode = "750";}
      // genAttrs cfg.hassGroupMembers (_: {extraGroups = ["hass"];});

    networking.firewall.allowedTCPPorts = [8123];

    services.openthread-border-router = mkIf cfg.thread.enable {
      enable = true;
      backboneInterfaces = [cfg.thread.backboneInterface];
      radio = {
        device = cfg.thread.radioDevice;
        baudRate = 460800;
        flowControl = false;
      };
      rest.listenAddress = "::1";
    };

    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = mkIf cfg.thread.enable (mkForce 1);

    services.matterjs-server = mkIf cfg.thread.enable {
      enable = true;
      listenAddress = "::1";
      bluetoothSupport = true;
    };

    networking.firewall.interfaces = mkIf cfg.thread.enable {
      ${cfg.thread.backboneInterface}.allowedUDPPorts = [5353];
    };
    networking.firewall.trustedInterfaces = mkIf cfg.thread.enable [config.services.openthread-border-router.interfaceName];
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeAssistant;

  palette = [[255 195 113] [255 160 0] [255 114 0] [157 0 6] [143 63 113] [104 157 106]];

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

  headingCard = {heading, ...}: {
    type = "heading";
    inherit heading;
  };

  averageCard = {class, ...}: {
    type = "history-graph";
    hours_to_show = 24;
    entities = [
      {
        entity = "sensor.average_${class}";
        name = "Average";
      }
    ];
  };

  deviceRows = ''
    {%- set classes = ${builtins.toJSON (map (c: c.class) climateClasses)} %}
    {%- set ns = namespace(rows=[], cells=[], cards=[], graph=[]) %}
    {%- for s in states.sensor | selectattr('attributes.device_class', 'defined') | selectattr('attributes.device_class', 'in', classes) | rejectattr('entity_id', 'in', integration_entities('mobile_app')) %}
      {%- set key = device_id(s.entity_id) or s.entity_id %}
      {%- set ns.cells = ns.cells + [{'key': key, 'class': s.attributes.device_class, 'entity': s.entity_id}] %}
      {%- if key not in ns.rows | map(attribute='key') | list %}
        {%- set ns.rows = ns.rows + [{'key': key, 'name': device_attr(key, 'name_by_user') or device_attr(key, 'name') or s.name}] %}
      {%- endif %}
    {%- endfor %}
    {%- set co2 = ns.cells | selectattr('class', 'eq', 'carbon_dioxide') | map(attribute='key') | list %}
    {%- set rows = ns.rows | sort(attribute='name') %}
    {%- for row in (rows | selectattr('key', 'in', co2) | list) + (rows | rejectattr('key', 'in', co2) | list) %}
      {%- for c in classes %}
        {%- set ns.graph = [] %}
        {%- for e in ns.cells | selectattr('key', 'eq', row.key) | selectattr('class', 'eq', c) | map(attribute='entity') %}
          {%- set ns.graph = ns.graph + [{'entity': e, 'name': row.name}] %}
        {%- endfor %}
        {%- if ns.graph %}
          {%- set ns.cards = ns.cards + [{'type': 'history-graph', 'hours_to_show': 24, 'entities': ns.graph}] %}
        {%- else %}
          {%- set ns.cards = ns.cards + [{'type': 'markdown', 'content': ' ', 'text_only': true}] %}
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
    {{ ns.cards }}
  '';

  climateDashboard = pkgs.writeText "climate.yaml" (builtins.toJSON {
    views = [
      {
        title = "Climate";
        type = "sections";
        max_columns = length climateClasses;
        sections = [
          {
            type = "grid";
            column_span = length climateClasses;
            cards = [
              {
                type = "custom:auto-entities";
                grid_options.columns = "full";
                card_param = "cards";
                card = {
                  type = "grid";
                  columns = length climateClasses;
                  square = false;
                };
                entities = map headingCard climateClasses ++ map averageCard climateClasses;
                filter.template = deviceRows;
              }
            ];
          }
        ];
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
      blueprints.automation = [(pkgs.replaceVars ./ikea-styrbar.yaml {palette = builtins.toJSON palette;})];
      customLovelaceModules = [pkgs.home-assistant-custom-lovelace-modules.auto-entities];
      config = {
        default_config = {};
        "automation ui" = "!include automations.yaml";
        "automation nixos" = import ./automations.nix {inherit sensors palette;};
        template = [{sensor = map averageSensor climateClasses;}];
        input_boolean.bathroom_manual.name = "Bathroom manual";
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

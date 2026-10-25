{
  sensors,
  palette,
}: let
  lightsOn = area: "area_entities('${area}') | select('match', 'light\\.') | select('is_state', 'on') | list | count";

  color = n: builtins.elemAt palette (n - 1);

  bathroomSchedule = [
    {
      from = 0;
      rgb = color 3;
      brightness = 1;
    }
    {
      from = 8;
      rgb = color 2;
      brightness = 50;
    }
    {
      from = 9;
      rgb = color 1;
      brightness = 100;
    }
    {
      from = 22;
      rgb = color 2;
      brightness = 100;
    }
    {
      from = 23;
      rgb = color 2;
      brightness = 50;
    }
  ];

  styrbar = id: alias: remote: area: color_index_helper: {
    inherit id alias;
    use_blueprint = {
      path = "ikea-styrbar.yaml";
      input = {inherit remote area color_index_helper;};
    };
  };

  climateAlert = id: alias: deviceClass: threshold: unit: duration: {
    inherit id alias;
    triggers = [
      {
        trigger = "template";
        value_template = "{{ ${sensors deviceClass} | map(attribute='state') | map('float') | select('gt', ${toString threshold}) | list | count > 0 }}";
        for = duration;
      }
    ];
    actions = [
      {
        variables.message = "{% set ns = namespace(high=[]) %}{% for s in ${sensors deviceClass} %}{% if s.state | float > ${toString threshold} %}{% set ns.high = ns.high + [s.name ~ ' ' ~ s.state ~ ' ${unit}'] %}{% endif %}{% endfor %}{{ ns.high | join(', ') if ns.high else 'Test, no sensor above ${toString threshold} ${unit}' }}";
      }
      {
        repeat = {
          for_each = "{{ integration_entities('mobile_app') | map('device_id') | reject('none') | unique | map('device_attr', 'name') | map('slugify') | list }}";
          sequence = [
            {
              action = "notify.mobile_app_{{ repeat.item }}";
              data = {
                title = alias;
                message = "{{ message }}";
              };
            }
          ];
        };
      }
    ];
  };
in [
  (styrbar "1770215585686" "Remote A1" "e212107c22737d3284e3100c2fb981f3" "living_room" "input_number.one_to_six")
  (styrbar "1770216514555" "Remote A2" "dd520d1c6bbe6e2cb502458024a7b5f1" "living_room" "input_number.one_to_six")
  (styrbar "1770217479974" "Remote B1" "47ee872251a509a205957fc30545ffb1" "kitchen" "input_number.slider_b")
  (styrbar "1770217595260" "Remote B2" "919984cb44787632a8492d1f3eccf43c" "kitchen" "input_number.slider_b")
  (styrbar "1771516552944" "Remote B3" "000afdfe339120d2eda2b784bf030fa3" "kitchen" "input_number.slider_b")
  (styrbar "1770218234756" "Remote C1" "8fa3134fa0b3121bee28782a7ba0b8f3" "bedroom" "input_number.slider_c")
  (styrbar "1770218262223" "Remote C2" "38a22b61069d668a53cee0f7a6d2e757" "bedroom" "input_number.slider_c")
  (styrbar "1772094774281" "Remote D1" "d44c7594be32a27de6bee92459f06fd9" "bathroom" "input_number.slider_d")
  {
    id = "bathroom_motion_light";
    alias = "Bathroom motion light";
    triggers = [
      {
        trigger = "state";
        entity_id = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy";
        to = "on";
      }
    ];
    conditions = [
      {
        condition = "state";
        entity_id = "input_boolean.bathroom_manual";
        state = "off";
      }
    ];
    actions = [
      {
        variables.slot = "{{ ${builtins.toJSON bathroomSchedule} | selectattr('from', 'le', now().hour) | list | last }}";
      }
      {
        action = "light.turn_on";
        target.area_id = "bathroom";
        data = {
          rgb_color = "{{ slot.rgb }}";
          brightness_pct = "{{ slot.brightness }}";
        };
      }
    ];
  }
  {
    id = "bathroom_motion_light_off";
    alias = "Bathroom motion light off";
    triggers = [
      {
        trigger = "state";
        entity_id = "binary_sensor.myggspray_wrlss_mtn_sensor_occupancy";
        to = "off";
        for.seconds = 30;
      }
    ];
    conditions = [
      {
        condition = "state";
        entity_id = "input_boolean.bathroom_manual";
        state = "off";
      }
    ];
    actions = [
      {
        action = "light.turn_off";
        target.area_id = "bathroom";
      }
    ];
  }
  {
    id = "bathroom_manual_on";
    alias = "Bathroom manual on";
    triggers = [
      {
        trigger = "event";
        event_type = "zha_event";
        event_data.device_id = "d44c7594be32a27de6bee92459f06fd9";
      }
    ];
    conditions = [
      {
        condition = "template";
        value_template = "{{ trigger.event.data.command != 'off' }}";
      }
    ];
    actions = [
      {
        action = "input_boolean.turn_on";
        target.entity_id = "input_boolean.bathroom_manual";
      }
    ];
  }
  {
    id = "bathroom_manual_off";
    alias = "Bathroom manual off";
    triggers = [
      {
        trigger = "template";
        value_template = "{{ ${lightsOn "bathroom"} == 0 }}";
      }
    ];
    actions = [
      {
        action = "input_boolean.turn_off";
        target.entity_id = "input_boolean.bathroom_manual";
      }
    ];
  }
  {
    id = "living_room_sunrise";
    alias = "Living room sunrise";
    mode = "single";
    triggers = [
      {
        trigger = "time";
        at = {
          entity_id = "sensor.naja_next_alarm";
          offset = "-00:30:00";
        };
      }
    ];
    conditions = [
      {
        condition = "template";
        value_template = "{{ ${lightsOn "living_room"} == 0 }}";
      }
      {
        condition = "template";
        value_template = "{% set alarm = states('sensor.naja_next_alarm') | as_datetime(none) %}{{ alarm is not none and 4 <= (alarm | as_local).hour < 10 }}";
      }
      {
        condition = "template";
        value_template = "{% set last = this.attributes.last_triggered %}{{ last is none or (last | as_local).date() != now().date() }}";
      }
    ];
    actions = let
      anyOn = {
        condition = "template";
        value_template = "{{ ${lightsOn "living_room"} > 0 }}";
      };
      fade = rgb: brightness: [
        anyOn
        {
          action = "light.turn_on";
          target.area_id = "living_room";
          data = {
            rgb_color = rgb;
            brightness_pct = brightness;
            transition = 600;
          };
        }
        {delay.seconds = 600;}
      ];
    in
      [
        {
          action = "light.turn_on";
          target.area_id = "living_room";
          data = {
            rgb_color = color 3;
            brightness_pct = 1;
          };
        }
      ]
      ++ fade (color 3) 30
      ++ fade (color 2) 65
      ++ fade (color 1) 100;
  }
  {
    id = "night_lights_off";
    alias = "Night lights off";
    triggers = [
      {
        trigger = "time";
        at = "03:30:00";
      }
    ];
    actions = [
      {
        action = "light.turn_off";
        target.entity_id = "all";
      }
    ];
  }
  (climateAlert "climate_alert_humidity" "High humidity" "humidity" 70 "%" {hours = 4;})
  (climateAlert "climate_alert_co2" "High CO2" "carbon_dioxide" 1200 "ppm" {minutes = 30;})
  (climateAlert "climate_alert_pm25" "High PM2.5" "pm25" 35 "µg/m³" {minutes = 30;})
]

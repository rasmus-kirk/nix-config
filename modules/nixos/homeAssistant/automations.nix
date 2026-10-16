{sensors}: let
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
        condition = "template";
        value_template = "{{ area_entities('bathroom') | select('match', 'light\\.') | select('is_state', 'on') | list | count == 0 }}";
      }
    ];
    actions = [
      {
        action = "light.turn_on";
        target.area_id = "bathroom";
        data = {
          rgb_color = [255 114 0];
          brightness_pct = 1;
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
        condition = "template";
        value_template = "{{ area_entities('bathroom') | select('match', 'light\\.') | select('is_state', 'on') | map('state_attr', 'brightness') | map('int', 0) | select('gt', 3) | list | count == 0 }}";
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
        value_template = "{{ area_entities('living_room') | select('match', 'light\\.') | select('is_state', 'on') | list | count == 0 }}";
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
        value_template = "{{ area_entities('living_room') | select('match', 'light\\.') | select('is_state', 'on') | list | count > 0 }}";
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
            rgb_color = [157 0 6];
            brightness_pct = 1;
          };
        }
      ]
      ++ fade [255 114 0] 30
      ++ fade [255 160 0] 65
      ++ fade [255 195 113] 100;
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

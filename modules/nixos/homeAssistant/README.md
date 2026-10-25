# Home Assistant module

`kirk.homeAssistant` runs Home Assistant on the desktop with ZHA (Zigbee),
and optionally a Thread border router with a Matter controller. Nix owns the
automations, the remote blueprint, the climate sensors and the climate
dashboard. The HA UI owns devices, areas, helpers created there, and any
automations made in the UI.

## Files

- `default.nix` holds the options, the HA service, the palette, the climate
  sensors and dashboard, and Thread/Matter.
- `automations.nix` holds every Nix-managed automation.
- `ikea-styrbar.yaml` is the blueprint for the IKEA STYRBAR remotes.

## Options

- `enable` turns on HA with ZHA.
- `stateDir` is the HA config directory.
- `hassGroupMembers` lists users that get read access to `stateDir`.
- `thread.enable` adds the OpenThread border router, the Matter server and
  IPv6 forwarding. `thread.radioDevice` is the RCP stick and
  `thread.backboneInterface` is the LAN interface.

HA listens on port 8123.

## Palette

`palette` in `default.nix` is the single list of six colors. Automations
refer to colors by their 1-based position with `color n`.

1. Warm white `[255 195 113]`
2. Yellow-orange `[255 160 0]`
3. Orange `[255 114 0]`
4. Red `[157 0 6]`
5. Purple `[143 63 113]`
6. Green `[104 157 106]`

Nix writes the palette into the blueprint at build time. The blueprint file
has a `@palette@` placeholder, so the raw file is not valid YAML.

## Remotes

Each STYRBAR remote uses the blueprint and controls every light in one area.

| Remote | Area | Color index helper |
|---|---|---|
| A1, A2 | Living room | `input_number.one_to_six` |
| B1, B2, B3 | Kitchen | `input_number.slider_b` |
| C1, C2 | Bedroom | `input_number.slider_c` |
| D1 | Bathroom | `input_number.slider_d` |

The color index helpers are created in the HA UI.

Buttons:

- UP turns the lights on. Each bulb comes back with its own last color and
  brightness.
- DOWN turns the lights off.
- Holding UP or DOWN ramps the brightness. The bulbs ramp by themselves from
  the remote's Zigbee commands.
- LEFT and RIGHT step through the palette and set the lights to that color at
  100%. The helper stores the position.
- Holding LEFT or RIGHT runs optional custom actions. No remote uses them now.

## Bathroom

The bathroom has two modes, stored in `input_boolean.bathroom_manual`.

**Auto mode** (flag off). The motion sensor turns the lights on with the
setting for the current hour.

| Time | Color | Brightness |
|---|---|---|
| 00:00 to 08:00 | 3, orange | 1% |
| 08:00 to 09:00 | 2, yellow-orange | 50% |
| 09:00 to 22:00 | 1, warm white | 100% |
| 22:00 to 23:00 | 2, yellow-orange | 100% |
| 23:00 to 00:00 | 2, yellow-orange | 50% |

The lights turn off after 30 seconds without motion. New motion while the
lights are on applies the setting for the current hour again.

**Manual mode** (flag on). Any press on remote D1 except DOWN turns the flag
on. The motion automations do nothing in this mode.

The flag turns off when all bathroom lights are off, for example from DOWN on
the remote or from the 03:30 all-off.

The schedule is `bathroomSchedule` in `automations.nix`. Each entry starts at
its `from` hour and lasts until the next entry.

## Living room sunrise

The living room wakes up 30 minutes before the next phone alarm
(`sensor.naja_next_alarm`). It runs only when:

- all living room lights are off,
- the alarm is between 04:00 and 10:00,
- it has not run yet today.

The lights start at orange 1%, then fade in three 10-minute steps to orange
30%, yellow-orange 65% and warm white 100%. If all lights are turned off
during the fade, the fade stops.

## Night lights off

At 03:30 every light turns off.

## Climate

`climateClasses` in `default.nix` lists temperature, humidity, CO2 and PM2.5.
For each class, HA uses every sensor with that device class, except sensors
from the phone app (`mobile_app`).

- **Average sensors.** `sensor.average_<class>` is the mean of all sensors in
  the class, rounded to one decimal.
- **Dashboard.** The Climate dashboard in the sidebar has one column per
  class. The first row shows the class names and the second row the average
  graphs. Then each device gets a row
  with a 24-hour graph per class, or an empty cell if the device does not
  measure that class. Devices with CO2 come first, then the rest, each group
  sorted by name.
- **Alerts.** A push notification goes to every phone with the HA app when a
  sensor stays above its threshold. The message lists the sensors that are
  over the threshold.

| Class | Threshold | For |
|---|---|---|
| Humidity | 70% | 4 hours |
| CO2 | 1200 ppm | 30 minutes |
| PM2.5 | 35 µg/m³ | 30 minutes |

## Notes for agents

- Templates are Jinja inside Nix strings. A regex dot is `'light\\.'` in Nix.
- `sensors class` and `lightsOn area` return Jinja expressions to embed in
  `{{ }}`.
- Remote IDs in `automations.nix` are ZHA device IDs. Find them in the HA UI.
- `configWritable` is on, and `automations.yaml` from the UI is included next
  to the Nix automations. Check the UI automations before you assume Nix has
  every automation.
- Verify a change with
  `nix eval .#nixosConfigurations.desktop.config.services.home-assistant.config --json`.

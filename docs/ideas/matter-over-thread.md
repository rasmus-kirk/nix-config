# Idea: Matter over Thread for the IKEA sensors

## Context

The new IKEA light sensor and humidity sensors speak Matter over Thread only.
The desktop runs Home Assistant 2026.9 with ZHA on a Sonoff Zigbee 3.0 Dongle
Plus V2 (ZBDongle-E, EFR32MG21,
`/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_f0885806cd14ef11abcb78b8bf9df066-if00-port0`).
That stick runs Zigbee firmware and cannot serve Thread at the same time.

Proposed model:

1. A second ZBDongle-E runs OpenThread RCP firmware. Bought from
   <https://www.proshop.dk/Smart-Home/Sonoff-Gateway-ZigBee-30-USB-Dongle-Plus/3213488>.
2. A systemd oneshot flashes the pinned RCP firmware onto that stick before
   the border router starts. It is a no-op when the firmware already matches.
   HA OS does this flash in its hardware wizard, NixOS does it here.
3. `services.openthread-border-router` (otbr-agent) drives the stick and
   routes between the Thread mesh and the LAN on `enp130s0`.
4. `services.matterjs-server` is the Matter controller. HA's `matter`
   integration connects to it over its WebSocket API.
5. HA gets the `thread`, `otbr` and `matter` integrations.

Only the sensors join Thread. All bulbs, including the new dual-protocol
bulbs, stay on Zigbee, so the STYRBAR remotes and blueprint keep working
unchanged.

Sensors are sleepy end devices and do not route. With no bulbs on Thread, the
border router is the only Thread router, and every sensor must reach the
desktop directly. If a sensor drops out, move one nearby dual-protocol bulb to
Thread so it routes for the sensor. That bulb then loses STYRBAR hold-to-dim,
because the blueprint dims through ZHA cluster commands.

Out of scope: IKEA DIRIGERA hub, Matter bridging of ZHA devices, Apple/Google
fabrics, bulbs on Thread.

## Changes

- `modules/nixos/homeAssistant/default.nix`:
  - Add options under `kirk.homeAssistant.thread`:
    - `enable`
    - `radioDevice` (str, `/dev/serial/by-id/...` path of the Thread stick)
    - `backboneInterface` (str, e.g. `enp130s0`)
  - When enabled:
    - Firmware: `pkgs.fetchurl` the ZBDongle-E OpenThread RCP `.gbl` from a
      pinned `silabs-firmware-builder` release (NabuCasa or darkxst). Pick
      the 460800 baud build.
    - `systemd.services.otbr-firmware`:
      - `Type = oneshot`, `RemainAfterExit = true`
      - `before` and `requiredBy` `otbr-agent.service`
      - `ExecStart` runs
        `universal-silabs-flasher --device <radioDevice> flash --firmware <gbl> --ensure-exact-version --allow-cross-flashing`
        from `python3Packages.universal-silabs-flasher` (1.1.0 in nixpkgs).
        Check `--help` for the exact flag names and whether the ZBDongle-E
        needs a `--bootloader-reset` value.
      - `--ensure-exact-version` makes repeat runs a no-op.
      - `radioDevice` must be the by-id path with the new stick's serial.
        Both sticks are the same model, and a wrong path flashes the Zigbee
        coordinator.
    - `services.openthread-border-router`:
      - `enable = true`
      - `backboneInterfaces = [cfg.thread.backboneInterface]`
      - `radio.device = cfg.thread.radioDevice`
      - `radio.baudRate = 460800`
      - `radio.flowControl = false` (otbr-agent fails to start on Sonoff
        sticks with hardware flow control, home-assistant/addons#4776)
      - `rest.listenAddress = "::1"` so only HA reaches the REST API
      - `web.enable = false`
    - `services.matterjs-server`:
      - `enable = true`
      - `listenAddress = "::1"`
      - `bluetoothSupport = true` so the desktop commissions sensors over BLE
        without the phone app (the desktop has `hardware.bluetooth`)
    - Add `"thread" "otbr" "matter"` to `services.home-assistant.extraComponents`.
    - Kernel sysctls on the backbone interface, required for Matter to reach
      Thread devices through the border router:
      - `net.ipv6.conf.<if>.accept_ra = 2`
      - `net.ipv6.conf.<if>.accept_ra_rt_info_max_plen = 64`
      - `net.ipv6.conf.all.forwarding = 1` (otbr-agent may set this itself,
        check the module before adding)
    - Firewall: open UDP 5353 (mDNS/SRP) and UDP 5540 (Matter operational)
      on the backbone interface. Use the modules' `openFirewall` where it
      covers this.
- `configurations/nixos/desktop/configuration.nix`: set
  `kirk.homeAssistant.thread = { enable = true; radioDevice = "/dev/serial/by-id/<new stick>"; backboneInterface = "enp130s0"; };`
- HA UI, one time (state lives in `stateDir`, not in Nix):
  1. Add the OpenThread Border Router integration with URL `http://[::1]:8081`.
  2. In the Thread integration, make the OTBR network the preferred network.
  3. Add the Matter integration with URL `ws://[::1]:5580/ws`.
  4. Commission each sensor from Settings → Devices → Add Matter device,
     with the sensor within BLE range of the desktop.

## Verification

1. `nix build .#nixosConfigurations.desktop.config.system.build.toplevel`
2. Plug in the new stick, read its by-id path from `ls -l /dev/serial/by-id/`,
   set `radioDevice`, switch.
3. `journalctl -u otbr-firmware` shows a flash on the first boot and a
   version match on the second.
4. `systemctl status otbr-agent matterjs-server home-assistant` all active.
5. `ot-ctl state` prints `leader` and `ot-ctl dataset active` shows a dataset.
6. `ip -6 route` shows a route to the Thread OMR prefix (`fdxx::/64`) via
   the backbone interface.
7. HA Thread integration lists the OTBR network as preferred.
8. Commission one humidity sensor. Its entities appear under the Matter
   integration and update.
9. Move the sensor to its final location. It stays available for 24 hours.
10. STYRBAR remotes still control their areas, and ZHA still uses the
    original stick.

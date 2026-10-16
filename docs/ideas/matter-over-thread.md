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
2. The RCP firmware is flashed onto that stick once, by hand, with
   `universal-silabs-flasher`. HA OS does this flash in its hardware wizard.
   Nix does not manage the firmware.
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
2. Flash the new stick once:
   1. Plug in only the new stick. Read its by-id path from
      `ls -l /dev/serial/by-id/`. Both sticks are the same model, so compare
      the serial against the Zigbee stick's path in Context. A wrong path
      flashes the Zigbee coordinator.
   2. Download
      `zbdonglee_openthread_rcp_2.5.3.0_GitHub-1fceb225b_gsdk_2024.6.3_no_flow_460800.gbl`
      from darkxst/silabs-firmware-builder release `20250627`. SHA-256
      `c949a49bea6a989a1998e19d9dc9e34c1cd8438ed6722a1228169d539350cf4e`.
      NabuCasa's releases have no ZBDongle-E build.
   3. Run
      `sudo universal-silabs-flasher --device <by-id path> flash --firmware <gbl> --bootloader-reset rts_dtr`
      with the flasher from `python3Packages.universal-silabs-flasher`
      (1.1.0). The tty needs root unless the user is in `dialout`.
   4. `sudo universal-silabs-flasher --device <by-id path> --bootloader-reset rts_dtr probe`
      reports `SPINEL` at 460800 baud.
3. Set `radioDevice` to the by-id path, switch.
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

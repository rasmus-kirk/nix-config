# Handoff: TV brightness from the Steam controller

You are picking this up on the **desktop** (Jovian, gamescope game mode, the
always-on box wired to the LG OLED). The design work happened on the laptop,
where the TV is not reachable, so nothing past the design could be verified.
Read this whole file before you touch anything.

## Goal

Adjust the LG TV's picture brightness from the Steam controller, in any game,
with no per-game Steam Input configuration.

## Why the obvious paths are dead

- **CEC.** The CEC user-control command set has no brightness opcode. This is
  why `kirk.cec` (`modules/home-manager/cec/default.nix`) handles power, volume
  and the speaker keep-alive but not brightness. Do not go looking again.
- **Steam Input keybind.** Every Steam Input layout is per-game. Rejected as a
  control surface for that reason.
- **`/sys/class/backlight` plus Steam's quick-access slider.** Needs a kernel
  backlight device. The TV does not answer DDC/CI over HDMI.
- **Steam controller over evdev.** Steam consumes the controller, so its input
  never reaches evdev. This is already documented in the volume-relay comment at
  `modules/home-manager/cec/default.nix:211`, and it is why that relay works by
  watching the PipeWire sink volume instead of reading keys.

## What was decided

webOS exposes brightness over SSAP, a JSON protocol on a WebSocket on the LAN.
So the TV joins the network, under a firewall that gives it no path out.

The control surface is a **Decky plugin**. Its quick-access tab opens over any
game with the QAM button, which satisfies "universal, not per-game" without
reverse-engineering HID reports.

A chord read straight from the controller's `hidraw` stream was considered and
rejected by the user. Do not revive it without asking. For the record, it was
viable: the new Steam Controller and its Puck (`28de:1304`) send a 54-byte
report `0x42` at ~266 Hz with the button bitfield at bytes `0x02`-`0x05`, and it
keeps streaming while Steam is connected.

## State of the work

| Item | Status |
|---|---|
| Design | Done, below |
| `modules/nixos/lgtv/src/lgtv_brightness.py` | Written. Imports and parses arguments. **Never talked to a TV.** |
| Everything else | Not started |

That Python file is a thin wrapper over `aiopylgtv` plus a CLI, about 260 lines.
It is not referenced by any Nix expression yet, so the repo does not build it.
Its argument parsing and its unreachable-host path were exercised on the laptop.
Nothing that touches the TV was, so treat every SSAP call in it as unverified.

## Step 1: isolate the TV, before it joins the network

The user's router is a GL.iNet running community OpenWrt. The TV must never
reach the internet, at any point. This is the whole reason it was not on the
network already.

The TV stays on the normal LAN and the normal SSID. Wi-Fi is fine. Isolation
comes from four things: DHCP withholds its gateway and resolver, the firewall
denies it the WAN, the firewall denies it the router itself, and every rule
matches its MAC so nothing depends on an address staying put.

The threat model is narrow and the user set it deliberately. The TV phoning home
is what matters. The TV seeing other LAN devices is **accepted**, because recon
has no value without an egress path. The one exception is the router admin
interface, because reaching that is how LAN access could turn into internet
access.

Pin the address and withhold the route and resolver, in `/etc/config/dhcp`:

```
config host
	option name 'lg-tv'
	option mac '<tv-mac>'
	option ip '192.168.1.50'
	option tag 'notv'

config tag 'notv'
	list dhcp_option '3'      # router: no value, so no default gateway
	list dhcp_option '6'      # dns: no value, so no resolver
```

An empty `dhcp_option` is dnsmasq's documented way to suppress an option
entirely, and the `tag` scopes it to this one host. A host with no default route
cannot leave the subnet even if a firewall rule is wrong.

Deny the WAN and the router, in `/etc/config/firewall`, with the DHCP allow
before the block:

```
config rule
	option name 'Allow-TV-DHCP'
	option src 'lan'
	option src_mac '<tv-mac>'
	option proto 'udp'
	option dest_port '67'
	option target 'ACCEPT'

config rule
	option name 'Block-TV-Router'      # no dest, so this is the input chain
	option src 'lan'
	option src_mac '<tv-mac>'
	option proto 'all'
	option family 'any'
	option target 'REJECT'

config rule
	option name 'Block-TV-WAN'
	option src 'lan'
	option dest 'wan'
	option src_mac '<tv-mac>'
	option proto 'all'
	option family 'any'
	option target 'REJECT'
```

`Block-TV-Router` closes LuCI, SSH and the resolver. Leaving port 53 open would
hand the TV a working exfiltration channel, because the router forwards those
queries upstream and DNS labels carry data.

`src_mac` with `family 'any'` matters more than it looks. **IPv6 router
advertisements are per-interface, so the DHCP suppression above does not cover
IPv6.** The TV gets an IPv6 default route from RA regardless. Matching on MAC
across both families is what closes it, because a SLAAC address with privacy
extensions rotates and an IP-based rule would not hold. Turning IPv6 off on the
LAN is the alternative, if the user does not need it.

On the TV: forget any saved SSID that has internet, skip the ThinQ and LG
account setup, decline the optional terms. No router configuration stops the
TV's own radio from joining some other open network. Only leaving it
unconfigured does.

Verify from the router, not from the TV:

```sh
conntrack -L | grep 192.168.1.50             # nothing toward the WAN
nft list ruleset | grep -B2 -A6 '<tv-mac>'   # all three rules, in order
logread | grep dnsmasq | grep 192.168.1.50   # lease handed out, no DNS served
```

Leave the counters on the block rules and check them after a day. A nonzero
count means the TV tried and the rules did their job.

**Do not build anything below until this verification passes.**

## Step 2: the TV control backend

This is the risky part and it is testable from a shell, so finish it before any
UI exists.

**Do not hand-roll an SSAP client.** `python3Packages.aiopylgtv` is already in
nixpkgs and does the protocol. Reading its source is the fastest way to
understand any of this:

```
/nix/store/*-python3.14-aiopylgtv-*/lib/python3.14/site-packages/aiopylgtv/
```

What it gives us:

- Pairing, the `com.lge.test` handshake, and client-key storage in a sqlitedict
  keyed by IP, at whatever `key_file_path` we pass.
- `get_picture_settings(keys)` at `webos_client.py:1627`, the public read path.
- `set_current_picture_settings(settings)` at `:1240`, the luna write path.
- `luna_request(uri, params)` at `:1162`, the alert-API hack the luna path rides
  on. The luna bus is not exposed to WebSocket clients, so `createAlert` carries
  the call and `closeAlert` dismisses it. It returns no data, so it cannot serve
  reads.
- `request(uri, payload)`, generic, which prepends `ssap://` for you.
- `send_message(text)`, a toast.

What it does not give us is the **public write path**,
`ssap://settings/setSystemSettings` with
`{"category":"picture","settings":{"<knob>":N}}`. `aiopylgtv` is from 2021 and
defines only the matching read endpoint. That path is the one newer firmware
takes, so the wrapper adds it in one call through the generic `request()`.

`aiopylgtv` is unmaintained upstream. `bscpylgtv` is the maintained fork and
knows more about webOS 23/24, but it is not in nixpkgs. The call was to use what
nixpkgs ships and add the five lines. Revisit only if the public path misbehaves
in a way the fork already solved.

The rest of `lgtv_brightness.py` is the part no library handles:

- **The knob has a different name per panel generation.** Ask for
  `["backlight","oled_light","brightness"]` and take the first key the TV
  returns. `backlight` is the expected answer on a 2023 OLED.
- **Some firmware wants the value as a JSON string, not a number, and says
  nothing when it dislikes the type.** So every write is read back, and a failed
  verification retries with the other type before the path is written off.
- Both answers are cached in the state file, so the steady state is one round
  trip per change.

CLI: `pair`, `probe`, `get`, `set N`, `up`, `down`, `status`.

State in `/var/lib/lgtv/state.json`, client keys in
`/var/lib/lgtv/client-keys.sqlite`, directory `0770 decky:decky` via
`systemd.tmpfiles`. The user joins the `decky` group so the CLI and the plugin
share one pairing. That group membership is the one privilege tradeoff in this
design, and it was accepted.

Packaging: a `buildPythonPackage` exposing `lgtv_brightness` as an importable
module plus a CLI wrapper, so the Decky backend imports the same code the CLI
runs. `aiopylgtv` is async, which suits the Decky backend, since plugin backends
are asyncio already.

## Step 3: the Decky plugin

`jovian.decky-loader.enable` exists in the pinned Jovian input, so enabling the
loader is one line. Plugins live in `/var/lib/decky-loader/plugins` and run as
the `decky` user.

**Backend** (`main.py`): a thin `Plugin` class over Step 2, exposing
`get_brightness`, `set_brightness`, `pair` and `status`. Make it importable
with:

```nix
jovian.decky-loader.extraPythonPackages = ps: [ ps.aiopylgtv lgtvPackage ];
```

Do not set the `_root` flag in `plugin.json`. The backend needs a TCP connection
and its state file, nothing more.

**Frontend** (`src/index.tsx`, around 80 lines): a `PanelSection` holding a
`SliderField` bound to the level, plus Day and Night preset buttons. Read the
current value on mount. Debounce slider writes to about 150 ms so dragging does
not flood the TV. Show a `toaster` line when the TV is unreachable.

**Packaging.** The frontend is real npm software and needs a real build, with
`pnpm.fetchDeps` and `pnpm.configHook` (pnpm 11.17 and Node 24 are in nixpkgs),
producing `dist/index.js` via `@decky/rollup`. Three things that will otherwise
cost you an hour:

- Vendor `package.json` and `pnpm-lock.yaml` in the repo. `pnpmDeps` needs a
  fixed-output hash, which you get from one deliberately failed build.
- The upstream template pins `@rollup/rollup-linux-x64-musl`. NixOS needs the
  `-gnu` variant.
- `@decky/ui` and `react` are externals resolved to Steam client globals, but
  `@decky/api` is a real dependency and gets bundled in. So hand-writing
  `dist/index.js` to dodge the npm toolchain does not work. Do not try.

**Installation.** Jovian's loader unit runs `chown -R` over its state directory
on every start, so do not point it at a store path. Add a oneshot unit ordered
before `decky-loader.service` that copies the built plugin directory into
`plugins/TVBrightness` and chowns it. Copy, not symlink, so the recursive chown
has nothing to fight with.

## Files to create or change

- `modules/nixos/lgtv/default.nix` (new). Options
  `kirk.lgtv.{enable, host, knob, step, min, max, presets}`. Builds the Python
  package and the plugin, installs the plugin, sets `extraPythonPackages`,
  creates the state directory, puts the CLI in `environment.systemPackages`.
- `modules/nixos/lgtv/src/lgtv_brightness.py` (exists, never talked to a TV).
- `modules/nixos/lgtv/plugin/` (new). `plugin.json`, `main.py`, `src/index.tsx`,
  `package.json`, `pnpm-lock.yaml`, `rollup.config.js`, `tsconfig.json`.
- `modules/nixos/default.nix`, add `./lgtv` to `imports`.
- `configurations/nixos/desktop/configuration.nix`, enable `kirk.lgtv` with the
  TV's pinned address, and `jovian.decky-loader.enable = true`.

This is a NixOS module, not a home-manager one, because `decky-loader` is a
system service. `kirk.cec` is not touched.

## Risks

1. **webOS 23/24 may refuse both write paths. This is the real unknown, and
   `probe` answers it in one command.** If both fail, what remains is injecting
   remote key presses to drive the on-screen menu, or Developer Mode, which
   needs an LG account and internet and is therefore ruled out. Stop and ask the
   user rather than building a worse workaround.
2. Picture settings are stored per picture mode, so Dolby Vision and Game mode
   each hold their own level. That is TV behaviour. Do not try to normalise it.
3. Decky's plugin API moves between major versions. The pinned lockfile keeps
   the build reproducible, but an upstream Decky update can still force a
   frontend change.
4. The QAM must be opened to change brightness. That is the accepted cost of
   dropping the chord.

## Verification

In order. Stop at the first failure.

```bash
# 0. on the OpenWrt box, before anything else
conntrack -L | grep <tv-ip>          # nothing toward the WAN

# 1. reachability
nc -z <tv-ip> 3000 && echo open

# 2. pairing, accept the prompt on the TV with the Magic Remote
lgtv-brightness pair

# 3. THE decision gate: which knob, which write method
lgtv-brightness probe

# 4. end to end, watching the actual panel
lgtv-brightness get
lgtv-brightness set 20 && lgtv-brightness get
lgtv-brightness up && lgtv-brightness get

# 5. plugin loaded
systemctl status decky-loader
journalctl -u decky-loader -b | grep -i tvbrightness
ls -l /var/lib/decky-loader/plugins/TVBrightness

# 6. the real test: open a game, press QAM, drag the slider
```

Then re-check the router counters. The TV still must have no path out.

## Conventions

- Commits in this repo are unsigned for agent work. The user batch-signs later.
- Follow the house style in `~/.claude/CLAUDE.md`: Simplified Technical English,
  no em dashes, no semicolons, laconic comments.
- Match the module style of `modules/home-manager/cec/default.nix`, which is the
  closest neighbour to this work.

## Sources

- SSAP endpoints, manifest and the luna alert trick:
  <https://github.com/chros73/bscpylgtv>
- webOS settings service:
  <https://www.webosose.org/docs/reference/ls2-api/com-webos-service-settings/>
- Steam Controller 2 HID reports, if the chord is ever revisited:
  <https://github.com/CouchTurtle/sc2-research>

"""Set an LG webOS TV's picture brightness over the LAN.

HDMI-CEC has no brightness opcode, so `kirk.cec` cannot do this. webOS exposes
it over SSAP, and `aiopylgtv` already speaks that protocol. It gives us
pairing, client-key storage, the public read path (`get_picture_settings`) and
the luna write path (`set_current_picture_settings`).

Three things are left to us, because no library handles them:

  * Which key this panel calls its brightness. It differs per generation.
  * Which of the two write paths this firmware allows. Newer firmware takes the
    public `setSystemSettings`, which `aiopylgtv` predates. Older firmware only
    takes the luna call.
  * A refused write is silent, and the value type matters. So every write is
    read back, and a failure retries with the other type.

Both answers are cached, so the steady state is one round trip per change.

The TV reaches nothing but this subnet. The router gives it no default route,
no resolver and no path to the WAN. See `docs/tv-brightness-handoff.md`.
"""

import argparse
import asyncio
import json
import os
import sys

from aiopylgtv import WebOsClient

DEFAULT_STATE = "/var/lib/lgtv/state.json"
DEFAULT_KEYS = "/var/lib/lgtv/client-keys.sqlite"

# The TV returns only the keys it has, so ask for all of them and take the
# first hit. `backlight` is the answer on a 2023 OLED.
KNOB_KEYS = ["backlight", "oled_light", "brightness"]

# The public write path. `aiopylgtv` knows the matching read endpoint but not
# this one, because it predates the firmware that accepts it.
SET_SYSTEM_SETTINGS = "settings/setSystemSettings"

WRITE_PATHS = ["public", "luna"]


class State:
    """The detected knob and the working write path.

    Kept next to the client key so the CLI and the Decky backend share one
    answer. Neither value is worth re-deriving on every call.
    """

    def __init__(self, path):
        self.path = path
        try:
            with open(path, encoding="utf-8") as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    def get(self, key):
        return self.data.get(key)

    def set(self, key, value):
        if self.data.get(key) == value:
            return
        self.data[key] = value
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, self.path)


class Brightness:
    """Brightness on one TV, over an already connected `WebOsClient`."""

    def __init__(self, client, state):
        self.tv = client
        self.state = state

    async def knob(self):
        cached = self.state.get("knob")
        if cached:
            return cached
        found = await self.tv.get_picture_settings(KNOB_KEYS)
        for key in KNOB_KEYS:
            if key in found:
                self.state.set("knob", key)
                return key
        raise LookupError("no known brightness key, TV offered %s" % sorted(found))

    async def level(self):
        key = await self.knob()
        found = await self.tv.get_picture_settings([key])
        if key not in found:
            raise LookupError("%s is not readable" % key)
        return int(found[key])

    async def _write(self, path, key, value):
        if path == "public":
            await self.tv.request(SET_SYSTEM_SETTINGS, {
                "category": "picture",
                "settings": {key: value},
            })
        else:
            await self.tv.set_current_picture_settings({key: value})

    async def _attempt(self, path, key, value):
        """Write by one path and read back. True if the panel actually moved."""
        for candidate in (value, str(value)):
            try:
                await self._write(path, key, candidate)
            except Exception:
                continue
            await asyncio.sleep(0.3)
            try:
                if await self.level() == value:
                    return True
            except Exception:
                pass
        return False

    async def set(self, value):
        """Set the level. Returns the write path that worked."""
        key = await self.knob()
        known = self.state.get("method")
        order = ([known] if known in WRITE_PATHS else [])
        order += [p for p in WRITE_PATHS if p != known]
        for path in order:
            if await self._attempt(path, key, value):
                self.state.set("method", path)
                return path
        raise RuntimeError(
            "neither write path changed %s, this firmware may not allow it" % key
        )

    async def step(self, delta, low, high):
        value = clamp(await self.level() + delta, low, high)
        return value, await self.set(value)


def clamp(value, low, high):
    return max(low, min(high, int(value)))


async def connect(args, pair=False):
    """Connect, registering if needed. Pairing prompts on the TV the first time."""
    client = WebOsClient(
        args.host,
        key_file_path=args.keys,
        timeout_connect=args.timeout,
    )
    await client.connect()
    if pair and not client.is_registered():
        raise RuntimeError("the TV did not accept the pairing prompt")
    return client


async def run(args):
    client = await connect(args, pair=args.cmd == "pair")
    state = State(args.state)
    panel = Brightness(client, state)
    try:
        return await args.run(args, panel)
    finally:
        await client.disconnect()


async def cmd_pair(args, panel):
    print("paired with %s" % args.host)
    return 0


async def cmd_get(args, panel):
    print(await panel.level())
    return 0


async def cmd_set(args, panel):
    value = clamp(args.value, args.min, args.max)
    path = await panel.set(value)
    await announce(args, panel, value)
    print("%d (%s)" % (value, path))
    return 0


async def cmd_up(args, panel):
    value, path = await panel.step(args.step, args.min, args.max)
    await announce(args, panel, value)
    print("%d (%s)" % (value, path))
    return 0


async def cmd_down(args, panel):
    value, path = await panel.step(-args.step, args.min, args.max)
    await announce(args, panel, value)
    print("%d (%s)" % (value, path))
    return 0


async def announce(args, panel, value):
    """A toast, because a picture-setting write raises no OSD of its own."""
    if not args.toast:
        return
    try:
        await panel.tv.send_message("Brightness %d" % value)
    except Exception:
        pass


async def cmd_status(args, panel):
    state = panel.state
    print("host:   %s" % args.host)
    print("knob:   %s" % (state.get("knob") or "(undetected)"))
    print("method: %s" % (state.get("method") or "(unknown)"))
    print("level:  %d" % await panel.level())
    return 0


async def cmd_probe(args, panel):
    """Answer the one question that decides whether any of this works."""
    found = await panel.tv.get_picture_settings(KNOB_KEYS)
    print("picture keys: %s" % (json.dumps(found) if found else "none"))
    key = await panel.knob()
    print("knob:         %s" % key)

    start = await panel.level()
    print("level:        %d" % start)

    # Move it far enough to see on the panel, then put it back.
    target = args.min if start > (args.min + args.max) // 2 else args.max
    worked = []
    for path in WRITE_PATHS:
        ok = await panel._attempt(path, key, target)
        print("%-6s write:  %s" % (path, "works" if ok else "no effect"))
        if ok:
            worked.append(path)
            await panel._attempt(path, key, start)

    if not worked:
        print("\nNeither path works. This firmware does not allow it.")
        return 1
    panel.state.set("method", worked[0])
    print("\nUsing: %s" % worked[0])
    return 0


def parse(argv):
    env = os.environ.get
    p = argparse.ArgumentParser(prog="lgtv-brightness")
    p.add_argument("--host", default=env("LGTV_HOST", ""))
    p.add_argument("--state", default=env("LGTV_STATE", DEFAULT_STATE))
    p.add_argument("--keys", default=env("LGTV_KEYS", DEFAULT_KEYS))
    p.add_argument("--step", type=int, default=int(env("LGTV_STEP", "5")))
    p.add_argument("--min", type=int, default=int(env("LGTV_MIN", "0")))
    p.add_argument("--max", type=int, default=int(env("LGTV_MAX", "100")))
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--toast", action="store_true",
                   default=env("LGTV_TOAST", "0") == "1")

    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("pair", help="register with the TV, once"
                   ).set_defaults(run=cmd_pair)
    sub.add_parser("probe", help="report the knob and the working write path"
                   ).set_defaults(run=cmd_probe)
    sub.add_parser("get", help="print the current level").set_defaults(run=cmd_get)
    setp = sub.add_parser("set", help="set the level")
    setp.add_argument("value", type=int)
    setp.set_defaults(run=cmd_set)
    sub.add_parser("up").set_defaults(run=cmd_up)
    sub.add_parser("down").set_defaults(run=cmd_down)
    sub.add_parser("status").set_defaults(run=cmd_status)
    return p.parse_args(argv)


def main(argv=None):
    args = parse(argv)
    if not args.host:
        print("no host, set --host or LGTV_HOST", file=sys.stderr)
        return 2
    try:
        return asyncio.run(run(args))
    except Exception as e:
        print("%s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())

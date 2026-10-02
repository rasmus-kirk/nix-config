import select
import time
from contextlib import suppress

import evdev
from util import POLL, info

RESCAN = 5.0
EV_KEY = evdev.ecodes.EV_KEY
KEY_SLEEP = evdev.ecodes.KEY_SLEEP
KEY_MUTE = evdev.ecodes.KEY_MUTE
VOLUME_KEYS = {
    evdev.ecodes.KEY_VOLUMEUP: "volume-up",
    evdev.ecodes.KEY_VOLUMEDOWN: "volume-down",
}

def has_volume_keys(dev):
    """
    Returns True for an input node with volume keys and no letter keys. That is the Consumer Control
    node, never a keyboard.
    """
    try:
        caps = dev.capabilities().get(EV_KEY, [])
    except OSError:
        return False
    if not any(key in caps for key in VOLUME_KEYS):
        return False
    return evdev.ecodes.KEY_A not in caps


class ControlKeys:
    """
    The sleep, volume and mute keys. The daemon can open only the input nodes that udev gives to
    its group, the System Control and Consumer Control nodes, and those have no letter keys.
    """

    def __init__(self, cec):
        """Stores cec. Opens no nodes until refresh."""
        self.cec = cec
        self.devs = {}
        self.last_rescan = 0.0

    def refresh(self):
        """
        Opens each new input node once and drops nodes that are gone. Grabs the volume key node, so
        the compositor does not also change the sink. Closing the node releases the grab.
        """
        self.last_rescan = time.monotonic()
        current = set(evdev.list_devices())
        for path in list(self.devs):
            if path not in current:
                self.devs.pop(path)
        for path in current - self.devs.keys():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            if has_volume_keys(dev):
                with suppress(OSError):
                    dev.grab()
                    info(f"grabbed {dev.name} (volume keys -> AVR only)")
            self.devs[path] = dev

    def read_keys(self, dev):
        """
        Handles the pending key events of dev. Forwards volume and mute to the AVR and returns True
        if the sleep key was pressed. Ignores all other keys and does not log them.
        """
        sleep_pressed = False
        for ev in dev.read():
            if ev.type != EV_KEY or ev.value not in (1, 2):
                continue
            pressed = ev.value == 1
            if ev.code == KEY_SLEEP:
                sleep_pressed |= pressed
            elif ev.code in VOLUME_KEYS:
                self.cec.volume_key(VOLUME_KEYS[ev.code], pressed)
            elif ev.code == KEY_MUTE and pressed:
                self.cec.volume_key("mute", True)
        return sleep_pressed

    def read(self):
        """
        Waits up to POLL for key events and handles them. Scans for input nodes every RESCAN.
        Returns True if the sleep key was pressed.
        """
        fds = {d.fd: d for d in self.devs.values()}
        try:
            ready, _, _ = select.select(list(fds), [], [], POLL)
        except OSError:
            ready = []
        sleep_pressed = False
        for fd in ready:
            dev = fds[fd]
            try:
                sleep_pressed |= self.read_keys(dev)
            except OSError:
                self.devs.pop(dev.path, None)
        if time.monotonic() - self.last_rescan >= RESCAN:
            self.refresh()
        return sleep_pressed

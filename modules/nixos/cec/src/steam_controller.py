import os
import select
import time
from contextlib import suppress
from pathlib import Path

from util import POLL

CONTROLLER_SCAN = 2.0
CONTROLLER_TIMEOUT = 3.0
CONTROLLER_SLEEP = 0.2
VALVE_VENDOR = "28DE"

def controller_hidraws():
    """
    Returns the hidraw nodes of Valve devices, which are the Steam controller and its receiver.
    logind gives the session user access to them, so no extra group is necessary.
    """
    try:
        names = os.listdir("/sys/class/hidraw")
    except OSError:
        return []
    paths = []
    for name in names:
        with suppress(OSError):
            if VALVE_VENDOR in Path("/sys/class/hidraw", name, "device", "uevent").read_text().upper():
                paths.append("/dev/" + name)
    return paths

class SteamController:
    """
    Steam controller presence. Steam reads the controller over hidraw, so evdev never sees its
    input. A controller sends hidraw reports for as long as it is on, in every input layout, so
    data on a Valve hidraw node means a controller is on.
    """

    def __init__(self):
        """No controller counts as present at start."""
        self.last_seen = 0.0
        self.was_present = False

    def watch(self):
        """
        Sets last_seen when a Valve hidraw node delivers data. Only a non-empty read counts. After a
        controller disconnects, the receiver leaves one node at EOF that select() reports as
        readable forever, so a node at EOF is closed and opened again on the next scan.
        """
        fds = {}
        last_scan = 0.0
        while True:
            now = time.monotonic()
            if now - last_scan >= CONTROLLER_SCAN:
                last_scan = now
                for path in controller_hidraws():
                    if path not in fds:
                        with suppress(OSError):
                            fds[path] = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            if not fds:
                time.sleep(CONTROLLER_SCAN)
                continue
            paths = {fd: path for path, fd in fds.items()}
            try:
                ready, _, _ = select.select(list(paths), [], [], POLL)
            except OSError:
                for fd in paths:
                    with suppress(OSError):
                        os.close(fd)
                fds.clear()
                continue
            got_data = False
            for fd in ready:
                try:
                    while True:
                        if not os.read(fd, 256):
                            raise EOFError
                        got_data = True
                except BlockingIOError:
                    pass
                except (OSError, EOFError):
                    with suppress(OSError):
                        os.close(fd)
                    fds.pop(paths[fd], None)
            if got_data:
                self.last_seen = time.monotonic()
            time.sleep(CONTROLLER_SLEEP)

    def poll(self, now):
        """
        Returns whether a controller is present, and whether it connected since the last poll. Only
        the main loop calls this.
        """
        present = now - self.last_seen < CONTROLLER_TIMEOUT
        connected = present and not self.was_present
        self.was_present = present
        return present, connected

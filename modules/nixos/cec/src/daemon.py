import signal
import time

from audio import Audio
from cec import Cec
from control_keys import ControlKeys
from steam_controller import SteamController
from util import debug, start

DEBUG_INTERVAL = 30.0

class Daemon:
    """Connects the parts and applies the TV rules once per tick."""

    def __init__(self, cfg):
        """Builds the parts. Starts no threads and opens no devices."""
        self.cfg = cfg
        self.cec = Cec(cfg)
        self.audio = Audio(cfg, self.cec)
        self.controller = SteamController()
        self.keys = ControlKeys(self.cec)
        self.last_activity = time.monotonic()
        self.last_debug = 0.0
        self.sleep_requested = False

    def on_sigusr1(self, signum, frame):
        """Handles SIGUSR1 as a sleep key press, so the system suspend action can toggle the TV."""
        self.sleep_requested = True

    def apply_rules(self, now, sleep_pressed, present, connected):
        """
        The sleep key toggles the TV. A controller that connects wakes it. Idle time without a
        controller puts it in standby. Sound only keeps the TV awake and never wakes it, so a
        manual standby holds while audio plays.
        """
        cec = self.cec
        if (self.audio.playing(now) and self.cfg.audioKeepsAwake) or present:
            self.last_activity = now
        if sleep_pressed:
            self.last_activity = now
            was = "on" if cec.tv_on else "off"
            cec.tv("standby" if cec.tv_on else "image-view-on", f"sleep button (tv was {was})")
        elif connected and not cec.tv_on:
            cec.tv("image-view-on", "controller connect")
        elif cec.tv_on and not present and now - self.last_activity >= self.cfg.idle_seconds:
            cec.tv("standby", f"idle {self.cfg.idleMinutes}min")

    def debug_status(self, now, present):
        """Logs power, RMS, silence, idle and controller state every DEBUG_INTERVAL."""
        if now - self.last_debug < DEBUG_INTERVAL:
            return
        self.last_debug = now
        debug(
            self.cfg,
            f"tv_on={self.cec.tv_on} rms={self.audio.last_rms:.4f} silence={now - self.audio.last_sound:.0f}s "
            f"idle={now - self.last_activity:.0f}s present={present}",
        )

    def tick(self):
        """Runs one pass of the main loop."""
        sleep_pressed = self.keys.read()
        if self.sleep_requested:
            self.sleep_requested = False
            sleep_pressed = True
        now = time.monotonic()
        present, connected = self.controller.poll(now)
        if connected:
            debug(self.cfg, "controller connect")
        self.apply_rules(now, sleep_pressed, present, connected)
        self.audio.keep_awake(now, self.cec.tv_on)
        self.debug_status(now, present)

    def run(self):
        """Registers on the CEC bus, starts the threads and runs the main loop."""
        signal.signal(signal.SIGUSR1, self.on_sigusr1)
        self.cec.register()
        start(self.cec.poll_power)
        start(self.controller.watch)
        self.audio.start()
        self.keys.refresh()
        while True:
            self.tick()

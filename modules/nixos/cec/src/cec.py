import re
import subprocess
import threading
import time

from util import info, output, run

CEC_TIMEOUT = 4
POWER_POLL = 5.0

def transmit_result(p):
    """Returns ok, no reply, nack/timeout or rc=N for a cec-ctl transmit, for the journal."""
    if p is None:
        return "no reply"
    if p.returncode != 0:
        return f"rc={p.returncode}"
    out = output(p)
    if "nack" in out or "timed out" in out or "error" in out:
        return "nack/timeout"
    return "ok"

class Cec:
    """
    The CEC bus and the TV power state. All cec-ctl calls go through one lock, so the power poll
    thread and the main loop do not interleave on the adapter.
    """

    def __init__(self, cfg):
        """Stores cfg. The TV counts as on until the first power poll replies."""
        self.cfg = cfg
        self.lock = threading.Lock()
        self.tv_on = True

    def cec_ctl(self, *args):
        """Runs cec-ctl on the adapter. Returns None if cec-ctl fails to start or times out."""
        try:
            return run(["cec-ctl", "-d", self.cfg.device, "-s", *args], timeout=CEC_TIMEOUT)
        except (OSError, subprocess.TimeoutExpired):
            return None

    def register(self):
        """
        Registers the playback logical address. Registration is a slow bus negotiation, so it runs
        once at start. The kernel keeps the address until an HPD event, for example a TV standby or
        wake.
        """
        with self.lock:
            return self.cec_ctl("--playback", "--osd-name", self.cfg.osdName)

    def send(self, *args):
        """
        Sends a CEC message on the registered address. If cec-ctl reports that the adapter is
        unconfigured after an HPD event, registers again and retries one time.
        """
        with self.lock:
            p = self.cec_ctl(*args)
            if p is not None and "unconfigured" in output(p):
                self.cec_ctl("--playback", "--osd-name", self.cfg.osdName)
                p = self.cec_ctl(*args)
            return p

    def power_status(self, la):
        """Returns on or off for the device at logical address la, or None if it does not reply."""
        p = self.send("--to", str(la), "--give-device-power-status")
        m = p and re.search(r"pwr-state:\s*(\S+)", p.stdout)
        if not m:
            return None
        return "on" if m.group(1).startswith("on") else "off"

    def poll_power(self):
        """
        Polls the real TV power state, so tv_on follows a standby by the TV timer or the TV remote.
        The daemon does not wake an AVR that went to standby, so a manual AVR standby holds.
        """
        while True:
            st = self.power_status(self.cfg.tvLogicalAddress)
            if st is not None:
                self.tv_on = st == "on"
            time.sleep(POWER_POLL)

    def tv(self, action, reason):
        """Sends action to the TV, logs reason and the result, and records the new TV power state."""
        info(f"{reason} -> {action}")
        p = self.send("--to", str(self.cfg.tvLogicalAddress), f"--{action}")
        info(f"{reason} -> {action}: {transmit_result(p)}")
        self.tv_on = action == "image-view-on"

    def volume_key(self, ui_cmd, log_it):
        """
        Sends ui_cmd to the audio system as a user control press and release. CEC volume goes to the
        AVR because the TV has no CEC control of its own speakers. Logs only when log_it is True, so
        autorepeat does not fill the journal.
        """
        if log_it:
            info(f"{ui_cmd} pressed -> audio system")
        to = ["--to", str(self.cfg.audioSystemLogicalAddress)]
        p = self.send(*to, "--user-control-pressed", f"ui-cmd={ui_cmd}", *to, "--user-control-released")
        if log_it:
            info(f"{ui_cmd}: {transmit_result(p)}")

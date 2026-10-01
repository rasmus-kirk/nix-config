import array
import math
import os
import re
import struct
import subprocess
import time
import wave
from contextlib import suppress
from pathlib import Path

from util import debug, info, quiet, run, start

AUDIO_WINDOW = 2.0
PACTL_TIMEOUT = 2
TONE_STOP_TIMEOUT = 3
RESTART_DELAY = 2.0
TONE_GRACE = 2.0
RATE = 8000
TONE_NAME = "cec-keepalive"

class Audio:
    """
    The TV sink. Records the sink monitor to detect sound, plays the keep-alive tone, and relays
    sink volume changes to the AVR.
    """

    def __init__(self, cfg, cec):
        """Stores cfg and cec. Silence counts from the time the daemon starts."""
        self.cfg = cfg
        self.cec = cec
        self.last_heard = 0.0
        self.last_rms = 0.0
        self.last_sound = time.monotonic()
        self.ignore_until = 0.0
        self.wav_path = None
        self.tone = None

    def target(self):
        """Returns the pw-play and pw-record arguments that pin a stream to the TV sink."""
        return [f"--target={self.cfg.sink}"] if self.cfg.sink else []

    def playing(self, now):
        """Returns True if the monitor heard sound in the last AUDIO_WINDOW."""
        return now - self.last_heard < AUDIO_WINDOW

    def record(self):
        """
        Records the TV sink monitor and stores the RMS of each one-second chunk. Sound at or above
        threshold sets last_heard. Chunks are skipped until ignore_until, so the keep-alive tone does
        not count as sound. Restarts pw-record if it exits.
        """
        cmd = ["pw-record", "--raw", "--format=s16", f"--rate={RATE}", "--channels=1", *self.target()]
        cmd += ["-P", "stream.capture.sink=true", "-"]
        while True:
            try:
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            except OSError:
                time.sleep(RESTART_DELAY)
                continue
            try:
                while buf := p.stdout.read(RATE * 2):
                    if time.monotonic() < self.ignore_until:
                        continue
                    samples = array.array("h")
                    samples.frombytes(buf[: len(buf) - len(buf) % 2])
                    if not samples:
                        continue
                    rms = math.sqrt(sum((s / 32768.0) ** 2 for s in samples) / len(samples))
                    self.last_rms = rms
                    if rms >= self.cfg.keepAwake.threshold:
                        self.last_heard = time.monotonic()
            except OSError:
                pass
            finally:
                p.terminate()
            time.sleep(RESTART_DELAY)

    def make_wav(self):
        """Writes the keep-alive tone to a WAV file in XDG_RUNTIME_DIR and returns its path."""
        keep = self.cfg.keepAwake
        n = RATE * max(1, keep.pulseSeconds)
        amp = keep.amplitude * 32767
        step = 2 * math.pi * keep.frequency / RATE
        path = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cec-keepalive.wav")
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(amp * math.sin(step * i))) for i in range(n)))
        return path

    def pulsing(self):
        """Returns True while the keep-alive tone plays."""
        return self.tone is not None and self.tone.poll() is None

    def pulse(self):
        """
        Starts the keep-alive tone on the TV sink, unless it already plays. The monitor ignores the
        sink until TONE_GRACE after the tone ends, so the tone and its tail do not count as sound.
        """
        if not self.wav_path or self.pulsing():
            return
        cmd = ["pw-play", "-P", f"media.name={TONE_NAME}", *self.target(), str(self.wav_path)]
        self.tone = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.ignore_until = time.monotonic() + self.cfg.keepAwake.pulseSeconds + TONE_GRACE
        debug(self.cfg, "keep-alive pulse")

    def stop_pulse(self):
        """Stops the keep-alive tone."""
        if self.pulsing():
            self.tone.terminate()
            try:
                self.tone.wait(timeout=TONE_STOP_TIMEOUT)
            except subprocess.TimeoutExpired:
                self.tone.kill()
        self.tone = None

    def keep_awake(self, now, tv_on):
        """
        While the TV is on, plays the keep-alive tone after silenceMinutes of silence. Stops the tone
        when the TV is off.
        """
        keep = self.cfg.keepAwake
        if self.playing(now):
            self.last_sound = now
        if not (tv_on and keep.enable):
            self.stop_pulse()
            return
        if not self.pulsing() and now - self.last_sound >= keep.silence_seconds:
            self.pulse()
            self.last_sound = now

    def sink_state(self):
        """Returns the TV sink volume in percent and its mute state, or None if pactl fails."""
        try:
            vol = run(["pactl", "get-sink-volume", self.cfg.sink], timeout=PACTL_TIMEOUT).stdout
            mute = run(["pactl", "get-sink-mute", self.cfg.sink], timeout=PACTL_TIMEOUT).stdout
        except (OSError, subprocess.TimeoutExpired):
            return None
        m = re.search(r"(\d+)%", vol)
        if not m:
            return None
        return int(m.group(1)), "yes" in mute

    def set_sink(self, pct):
        """Sets the TV sink volume to pct percent."""
        with suppress(OSError, subprocess.TimeoutExpired):
            quiet(["pactl", "set-sink-volume", self.cfg.sink, f"{pct}%"], timeout=PACTL_TIMEOUT)

    def relay(self):
        """
        Sends the difference between the TV sink volume and referencePercent to the AVR as CEC
        volume steps, then sets the sink back to referencePercent. A muted sink is ignored.
        """
        relay = self.cfg.controllerVolume
        st = self.sink_state()
        if st is None:
            return
        vol, muted = st
        if muted or vol == relay.referencePercent:
            return
        delta = vol - relay.referencePercent
        steps = max(1, round(abs(delta) / relay.stepPercent))
        cmd = "volume-up" if delta > 0 else "volume-down"
        for _ in range(steps):
            self.cec.volume_key(cmd, False)
        info(f"controller volume {cmd} x{steps} -> AVR (sink was {vol}%)")
        self.set_sink(relay.referencePercent)

    def watch_volume(self):
        """
        Holds the TV sink at referencePercent. Runs relay on each sink change event from pactl
        subscribe. The reset to referencePercent also makes an event, but it reads as no change, so
        there is no feedback loop.
        """
        self.set_sink(self.cfg.controllerVolume.referencePercent)
        while True:
            try:
                p = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            except OSError:
                time.sleep(RESTART_DELAY)
                continue
            self.relay()
            for line in p.stdout:
                if "'change' on sink #" in line:
                    self.relay()
            p.wait()
            time.sleep(RESTART_DELAY)

    def start(self):
        """
        Writes the tone and starts the recorder if keepAwake is on. Starts the volume relay if
        controllerVolume is on.
        """
        if self.cfg.keepAwake.enable:
            try:
                self.wav_path = self.make_wav()
            except OSError:
                self.wav_path = None
            start(self.record)
        if self.cfg.controllerVolume.enable:
            start(self.watch_volume)

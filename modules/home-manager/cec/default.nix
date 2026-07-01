{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.cec;

  # Single TV-liveness manager for the always-on box. It subsumes rustle:
  # the box never powers off, so the TV follows *activity*, not power, and the
  # speaker keep-alive only makes sense while the TV is actually on.
  #
  # The daemon tracks the TV's REAL power state (polled over CEC), not just
  # what it last commanded — so it wakes the TV on input no matter how it went
  # to standby (its own idle timeout, the LG remote, or a manual standby).
  #
  # Security: the daemon NEVER reads keyboards. A udev rule grants it (via the
  # `cectv` group) exactly two nodes — /dev/cec0 and the keystroke-free
  # "System Control" sleep-key node — so the only key it can read is the
  # repurposed sleep button. Controller presence is read from world-readable
  # sysfs; the user is in neither `input` nor `video`.
  #
  # CEC:
  #   * Wake (image-view-on): the sleep button (KEY_SLEEP on the System-Control
  #     node, which carries no letters) or a controller connecting, while the
  #     TV is off.
  #   * Sleep (standby): no sleep-button press, no TV audio, and no controller
  #     connected, for idleMinutes.
  #   (A Steam controller's input is invisible to evdev — Steam reads it over
  #    hidraw — so we use its *presence* (sysfs) to block sleep and its
  #    *connect* (udev) to wake; we never read its input.)
  #
  # Keep-alive (rustle, emulated): record the TV sink's monitor, RMS each ~1s;
  # after silenceMinutes of silence play a sub-audible pulse for pulseSeconds,
  # reset on real sound. Monitor + pulse are PINNED to the TV's HDMI sink
  # (keepAwake.sink), so headphones becoming the default sink don't affect the
  # TV and the pulse lands on the TV speakers. We ignore the monitor while WE
  # pulse so our poke isn't mistaken for audio.
  daemon = pkgs.writers.writePython3Bin "cec-tv-liveness" {
    libraries = [pkgs.python3Packages.evdev];
    flakeIgnore = ["E501" "E722" "E302" "E305" "E306" "W391" "E741" "E402"];
  } ''
    import array
    import math
    import os
    import re
    import select
    import struct
    import subprocess
    import threading
    import time
    import wave

    import evdev

    CEC_CTL = os.environ.get("CEC_CTL", "cec-ctl")
    PW_PLAY = os.environ.get("PW_PLAY", "pw-play")
    PW_RECORD = os.environ.get("PW_RECORD", "pw-record")
    DEV = os.environ.get("CEC_DEV", "/dev/cec0")
    OSD = os.environ.get("OSD_NAME", "Desktop")
    TV = os.environ.get("TV_LA", "0")
    AUDIO_LA = os.environ.get("AUDIO_LA", "5")
    IDLE = int(os.environ.get("IDLE_SECONDS", "1200"))
    AUDIO_AWAKE = os.environ.get("AUDIO_KEEPS_AWAKE", "1") == "1"
    SINK = os.environ.get("SINK", "")

    KEEPALIVE = os.environ.get("KEEPALIVE", "0") == "1"
    SILENCE = int(os.environ.get("SILENCE_SECONDS", "600"))
    PULSE_SECONDS = int(os.environ.get("PULSE_SECONDS", "10"))
    TONE_FREQ = int(os.environ.get("TONE_FREQ", "20"))
    TONE_AMP = float(os.environ.get("TONE_AMP", "0.05"))
    THRESHOLD = float(os.environ.get("THRESHOLD", "0.001"))
    DEBUG = os.environ.get("DEBUG", "0") == "1"
    TONE_NAME = "cec-keepalive"

    POLL = 1.0
    RESCAN = 5.0
    RATE = 8000
    PWR_POLL = 5.0   # how often to read the TV's real power state
    EV_KEY = 1
    KEY_SLEEP = 142
    KEY_POWER = 116
    KEY_VOLUMEUP = 115
    KEY_VOLUMEDOWN = 114
    KEY_MUTE = 113
    UDEVADM = os.environ.get("UDEVADM", "udevadm")

    cec_lock = threading.Lock()
    tone_proc = None
    wav_path = None
    g_last_audio = 0.0
    g_last_rms = 0.0
    g_poking = False
    g_tv_on = True   # real TV power, kept current by power_monitor
    g_phys = None    # our physical address (read once), operand for AVR wake
    g_last_ctrl = 0.0  # monotonic time of the last Steam-Controller hidraw data
    CTRL_TIMEOUT = 3.0  # no controller hidraw data for this long => it's off
    udev_w = -1      # write end of the self-pipe poked on input add/remove

    def log(msg):
        if DEBUG:
            print("[cec] " + msg, flush=True)

    def note(msg):
        # Operational, always-on, content-free: which response key fired and
        # what the TV was told. Only ever called for sleep/power/volume/mute.
        print("[cec] " + msg, flush=True)

    def cec(*args):
        # No args -> (re)register our Playback logical address. This runs the
        # logical-address allocation, a slow bus negotiation (~100s of ms), so
        # we do it ONCE (startup) and reuse the address: the kernel keeps it
        # across cec-ctl runs; only an HPD event (TV standby/wake or a replug)
        # clears it.
        #
        # With args -> transmit on the already-claimed address (fast, no
        # re-registration). If an HPD cleared it, cec-ctl prints "unconfigured"
        # and refuses; we then re-register and retry once. This keeps frequent
        # transmits (volume) snappy while still self-healing after the TV
        # sleeps/wakes.
        reg = ["--playback", "--osd-name", OSD]
        with cec_lock:
            if not args:
                return subprocess.run([CEC_CTL, "-d", DEV, "-s", *reg],
                                      capture_output=True, text=True)
            p = subprocess.run([CEC_CTL, "-d", DEV, "-s", *args],
                               capture_output=True, text=True)
            if "unconfigured" in ((p.stdout or "") + (p.stderr or "")).lower():
                subprocess.run([CEC_CTL, "-d", DEV, "-s", *reg],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                p = subprocess.run([CEC_CTL, "-d", DEV, "-s", *args],
                                   capture_output=True, text=True)
            return p

    def cec_result(p):
        # Concise transmit outcome for the journal: ok / nack-timeout / rc=N.
        out = ((p.stdout or "") + (p.stderr or "")).lower()
        if p.returncode != 0:
            return "rc=%d" % p.returncode
        if "nack" in out or "timed out" in out or "error" in out:
            return "nack/timeout"
        return "ok"

    def configure():
        cec()

    def cec_vol(ui_cmd, log_it):
        # Forward a volume/mute key to the audio system (AVR/soundbar) as a CEC
        # user-control press + release (ui-cmd: volume-up / volume-down / mute).
        # Volume over CEC is "System Audio Control": it targets the Audio System
        # (logical addr 5), NOT the TV -- the TV has no CEC concept of its own
        # speaker volume, so this only does anything when an AVR is present and
        # the TV is in system-audio mode. Logged once per press (log_it; not on
        # autorepeat): the action, then the transmit outcome.
        if log_it:
            note("%s pressed -> audio system" % ui_cmd)
        p = cec("--to", AUDIO_LA, "--user-control-pressed", "ui-cmd=" + ui_cmd,
                "--to", AUDIO_LA, "--user-control-released")
        if log_it:
            note("%s: %s" % (ui_cmd, cec_result(p)))

    def dev_power(la):
        with cec_lock:
            try:
                out = subprocess.run(
                    [CEC_CTL, "-d", DEV, "-s", "--to", la,
                     "--give-device-power-status"],
                    capture_output=True, text=True, timeout=4).stdout
            except Exception:
                return None
        m = re.search(r"pwr-state:\s*(\S+)", out)
        if not m:
            return None
        return "on" if m.group(1).startswith("on") else "off"

    def read_phys():
        # Our own physical address (e.g. 4.0.0.0). It's the operand of the
        # System Audio Mode Request we use to wake the AVR. Read once; it only
        # changes if the HDMI topology does.
        global g_phys
        with cec_lock:
            try:
                out = subprocess.run([CEC_CTL, "-d", DEV],
                                     capture_output=True, text=True,
                                     timeout=4).stdout
            except Exception:
                return
        m = re.search(r"Physical Address\s*:\s*(\S+)", out)
        if m:
            g_phys = m.group(1)

    def power_monitor():
        # Track the TV's real power every PWR_POLL seconds, and back-stop the
        # AVR. rustle's tone is the PRIMARY keep-awake; but if it ever fails and
        # the AVR drops to standby while the TV is on, the user gets a jarring
        # HDMI re-negotiation / output switch. We can't PREVENT that over CEC
        # (the AVR's eco-standby only resets on a real audio signal), but we
        # catch it within PWR_POLL seconds and wake it straight back. A "waking"
        # log line therefore means the tone failed and needs tuning.
        global g_tv_on
        while True:
            st = dev_power(TV)
            if st == "on":
                g_tv_on = True
            elif st == "off":
                g_tv_on = False
            if AUDIO_LA and g_phys and g_tv_on and dev_power(AUDIO_LA) == "off":
                note("AVR in standby while TV on -> waking")
                cec("--to", AUDIO_LA, "--system-audio-mode-request",
                    "phys-addr=" + g_phys)
            time.sleep(PWR_POLL)

    def make_wav():
        n = RATE * max(1, PULSE_SECONDS)
        rt = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        path = os.path.join(rt, "cec-keepalive.wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            frames = bytearray()
            for i in range(n):
                v = int(TONE_AMP * 32767 * math.sin(2 * math.pi * TONE_FREQ * i / RATE))
                frames += struct.pack("<h", v)
            w.writeframes(bytes(frames))
        return path

    def tone_running():
        return tone_proc is not None and tone_proc.poll() is None

    def poke():
        global tone_proc, g_poking
        if not (KEEPALIVE and wav_path) or tone_running():
            return
        cmd = [PW_PLAY, "-P", "media.name=" + TONE_NAME]
        if SINK:
            cmd.append("--target=" + SINK)
        cmd.append(wav_path)
        tone_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        g_poking = True
        log("keep-alive pulse")

    def tone_stop():
        global tone_proc, g_poking
        if tone_running():
            tone_proc.terminate()
            try:
                tone_proc.wait(timeout=3)
            except Exception:
                tone_proc.kill()
        tone_proc = None
        g_poking = False

    def audio_monitor():
        global g_last_audio, g_last_rms
        chunk = RATE * 2
        while True:
            cmd = [PW_RECORD, "--raw", "--format=s16", "--rate=" + str(RATE),
                   "--channels=1"]
            if SINK:
                cmd.append("--target=" + SINK)
            cmd += ["-P", "stream.capture.sink=true", "-"]
            try:
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL)
            except Exception:
                time.sleep(2)
                continue
            try:
                while True:
                    buf = p.stdout.read(chunk)
                    if not buf:
                        break
                    if g_poking:
                        continue
                    samples = array.array("h")
                    samples.frombytes(buf[:len(buf) - (len(buf) % 2)])
                    if not samples:
                        continue
                    ss = 0.0
                    for s in samples:
                        ss += (s / 32768.0) ** 2
                    rms = math.sqrt(ss / len(samples))
                    g_last_rms = rms
                    if rms >= THRESHOLD:
                        g_last_audio = time.monotonic()
            except Exception:
                pass
            finally:
                try:
                    p.terminate()
                except Exception:
                    pass
            time.sleep(2)

    def udev_monitor():
        # Real-time input add/remove. Pokes the main loop's self-pipe so a
        # controller connecting triggers an immediate rescan (and wake) rather
        # than waiting up to RESCAN seconds.
        while True:
            try:
                p = subprocess.Popen(
                    [UDEVADM, "monitor", "--udev", "--subsystem-match=input"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for line in p.stdout:
                    if (" add " in line or " remove " in line) and udev_w >= 0:
                        try:
                            os.write(udev_w, b"x")
                        except OSError:
                            pass
            except Exception:
                pass
            time.sleep(2)

    def has_volume(dev):
        # True for the node that carries the volume keys (the Consumer Control
        # node) -- but NEVER a real keyboard: a node that also has letters is
        # excluded so we don't grab (and steal) all typing from the desktop.
        try:
            caps = dev.capabilities().get(EV_KEY, [])
        except Exception:
            return False
        if KEY_VOLUMEUP not in caps and KEY_VOLUMEDOWN not in caps:
            return False
        return evdev.ecodes.KEY_A not in caps

    def refresh_devices(devs):
        # Open every input node we can, each exactly once (mutates `devs`), and
        # drop nodes that vanished. The node carrying the volume keys is GRABBED
        # (EVIOCGRAB) so the desktop never sees those keys -- we forward
        # volume/mute to the AVR ourselves, and without the grab the compositor
        # would ALSO change the box sink, double-attenuating the audio feeding
        # the AVR. The grab is exclusive and released automatically when the
        # node is dropped (its fd closed).
        cur = set(evdev.list_devices())
        for p in list(devs):
            if p not in cur:
                devs.pop(p, None)
        for p in cur:
            if p in devs:
                continue
            try:
                d = evdev.InputDevice(p)
            except OSError:
                continue
            if has_volume(d):
                try:
                    d.grab()
                    note("grabbed %s (volume keys -> AVR only)" % d.name)
                except OSError:
                    pass
            devs[p] = d

    def find_controller_hidraws():
        # /dev/hidrawN nodes belonging to Valve (vendor 0x28de) -- the Steam
        # Controller and its wireless dongle. logind's uaccess ACL grants the
        # session user rw on them, so no extra group is needed.
        paths = []
        try:
            names = os.listdir("/sys/class/hidraw")
        except OSError:
            return paths
        for n in names:
            try:
                with open("/sys/class/hidraw/%s/device/uevent" % n) as f:
                    if "28DE" in f.read().upper():
                        paths.append("/dev/" + n)
            except OSError:
                pass
        return paths

    def controller_monitor():
        # A Steam Controller streams hidraw reports (IMU/status) continuously
        # the whole time it is powered on -- independent of Steam, the game, or
        # the input layout. So *real data* flowing on a Valve hidraw is a robust,
        # layout-independent "a controller is on" signal, unlike the virtual
        # gamepad's BTN_SOUTH (which only appears for gamepad-layout games -- not
        # keyboard/mouse layouts or desktop mode). We only watch for data flow;
        # the report contents are irrelevant and discarded (no input is logged).
        #
        # Two footguns, both about the always-connected Steam Controller Puck
        # (the receiver/dock): after a controller has connected and dropped, one
        # of the Puck's hidraw interfaces sits at EOF/HUP -- select() reports it
        # readable forever while os.read() returns NO bytes. So:
        #   1. only a NON-EMPTY read counts as activity (an empty read is EOF,
        #      not a controller report -- counting it pinned `present` true and
        #      the TV never slept); and
        #   2. an fd that hits EOF/HUP is retired (closed) and reopened fresh on
        #      the next scan, so a hung fd can't spin as "readable" forever.
        global g_last_ctrl
        fds = {}          # path -> open fd
        last_scan = 0.0
        while True:
            now = time.monotonic()
            if now - last_scan >= 2.0:
                last_scan = now
                for path in find_controller_hidraws():
                    if path not in fds:
                        try:
                            fds[path] = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                        except OSError:
                            pass
            if not fds:
                time.sleep(2)
                continue
            rev = {fd: path for path, fd in fds.items()}
            try:
                r, _, _ = select.select(list(rev), [], [], 1.0)
            except OSError:
                for path, fd in list(fds.items()):
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    fds.pop(path, None)
                continue
            got_data = False
            for fd in r:
                try:
                    while True:
                        if not os.read(fd, 256):
                            raise EOFError  # EOF/HUP: not a report -> retire
                        got_data = True     # a real, non-empty controller report
                except BlockingIOError:
                    pass                    # drained (EAGAIN) -- fd stays open
                except (OSError, EOFError):
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    fds.pop(rev.get(fd), None)
            if got_data:
                g_last_ctrl = time.monotonic()
            time.sleep(0.2)

    def main():
        global wav_path, g_tv_on, udev_w
        configure()
        read_phys()
        st = dev_power(TV)
        if st is not None:
            g_tv_on = (st == "on")
        if KEEPALIVE:
            try:
                wav_path = make_wav()
            except Exception:
                wav_path = None
            threading.Thread(target=audio_monitor, daemon=True).start()
        threading.Thread(target=power_monitor, daemon=True).start()
        threading.Thread(target=controller_monitor, daemon=True).start()
        udev_r, udev_w = os.pipe()
        os.set_blocking(udev_r, False)
        threading.Thread(target=udev_monitor, daemon=True).start()

        devs = {}
        refresh_devices(devs)
        was_present = False
        now = time.monotonic()
        last_activity = now
        last_rescan = now
        last_sound = now
        last_debug = 0.0

        while True:
            fds = {d.fd: d for d in devs.values()}
            try:
                r, _, _ = select.select(list(fds) + [udev_r], [], [], POLL)
            except OSError:
                r = []
            now = time.monotonic()
            sleep_pressed = False   # the sleep button was pressed this tick
            udev_event = False

            for fd in r:
                if fd == udev_r:
                    try:
                        os.read(udev_r, 4096)
                    except OSError:
                        pass
                    udev_event = True  # input device added/removed -> rescan now
                    continue
                d = fds.get(fd)
                if d is None:
                    continue
                try:
                    for ev in d.read():
                        if ev.type != EV_KEY:
                            continue
                        if ev.value not in (1, 2):  # key-down or autorepeat
                            continue
                        # Act on (and log) only these response keys; every
                        # other key -- letters included -- is ignored silently
                        # and never logged.
                        if ev.code in (KEY_SLEEP, KEY_POWER):
                            if ev.value == 1:
                                sleep_pressed = True       # toggle TV power
                        elif ev.code == KEY_VOLUMEUP:
                            cec_vol("volume-up", ev.value == 1)
                        elif ev.code == KEY_VOLUMEDOWN:
                            cec_vol("volume-down", ev.value == 1)
                        elif ev.code == KEY_MUTE and ev.value == 1:
                            cec_vol("mute", True)
                except OSError:
                    devs.pop(d.path, None)

            if udev_event or now - last_rescan >= RESCAN:
                refresh_devices(devs)
                last_rescan = now

            # Controller presence from the hidraw monitor (layout-independent).
            present = (now - g_last_ctrl) < CTRL_TIMEOUT
            connect = present and not was_present  # a controller just turned on
            was_present = present
            if connect and DEBUG:
                log("controller connect")

            real_audio = (now - g_last_audio) < 2.0
            if real_audio:
                last_sound = now

            # Audio playing, or a controller present, keeps it awake.
            if (real_audio and AUDIO_AWAKE) or present:
                last_activity = now

            # Sleep button = explicit power TOGGLE (awake -> standby,
            # asleep -> wake). Otherwise: a controller connecting wakes a
            # sleeping TV, and idle (no audio, no controller) sleeps it. Audio
            # only KEEPS the TV awake -- it never auto-wakes -- so a manual
            # standby sticks even while sound is still routed to the TV sink.
            if sleep_pressed:
                last_activity = now
                action = "standby" if g_tv_on else "image-view-on"
                note("sleep button pressed (tv was %s) -> %s"
                     % ("on" if g_tv_on else "off", action))
                p = cec("--to", TV, "--" + action)
                note("sleep button -> %s: %s" % (action, cec_result(p)))
                g_tv_on = not g_tv_on
            elif connect and not g_tv_on:
                note("controller connect -> image-view-on")
                p = cec("--to", TV, "--image-view-on")
                note("controller connect -> image-view-on: %s" % cec_result(p))
                g_tv_on = True
            elif (now - last_activity) >= IDLE and not present:
                if g_tv_on:
                    note("idle %ds -> standby" % IDLE)
                    p = cec("--to", TV, "--standby")
                    note("idle -> standby: %s" % cec_result(p))
                    g_tv_on = False

            if g_tv_on and KEEPALIVE:
                if g_poking and not tone_running():
                    tone_stop()
                if not tone_running() and (now - last_sound) >= SILENCE:
                    poke()
                    last_sound = now
            else:
                tone_stop()

            if DEBUG and now - last_debug >= 30:
                last_debug = now
                log("tv_on=%s rms=%.4f silence=%ds idle=%ds present=%s" % (
                    g_tv_on, g_last_rms, int(now - last_sound),
                    int(now - last_activity), present))

    if __name__ == "__main__":
        main()
  '';
in {
  options.kirk.cec = {
    enable = mkEnableOption "HDMI-CEC TV-liveness daemon (sleep TV on idle, wake on input; subsumes rustle)";

    device = mkOption {
      type = types.str;
      default = "/dev/cec0";
      description = "CEC adapter device node (needs the `video` group).";
    };

    osdName = mkOption {
      type = types.str;
      default = "Desktop";
      description = "OSD name this device reports to the TV.";
    };

    idleMinutes = mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = "Minutes with no key/button input and no TV audio before standby.";
    };

    tvLogicalAddress = mkOption {
      type = types.int;
      default = 0;
      description = "CEC logical address of the TV (0 in virtually all setups).";
    };

    audioSystemLogicalAddress = mkOption {
      type = types.int;
      default = 5;
      description = ''
        CEC logical address of the audio system (AVR/soundbar) that the
        volume/mute keys control via System Audio Control (5 in virtually all
        setups). The TV's own speaker volume is not CEC-controllable, so volume
        keys only do anything when such a device is present.
      '';
    };

    sink = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra2";
      description = ''
        PipeWire node.name of the TV's audio sink. The keep-alive monitor and
        pulse are pinned to it, so default-sink switching (e.g. headphones)
        doesn't affect the TV. null = follow the default sink.
      '';
    };

    audioKeepsAwake = mkOption {
      type = types.bool;
      default = true;
      description = "Treat real audio on the TV sink (monitor RMS) as activity.";
    };

    keepAwake = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Emulate rustle: while the TV is on, watch the TV sink monitor and,
          after silenceMinutes of silence, play a sub-audible sine for
          pulseSeconds so the speaker doesn't hit its EU-mandated standby.
          Reset on real sound; nothing while the TV is off.
        '';
      };

      silenceMinutes = mkOption {
        type = types.ints.unsigned;
        default = 10;
        description = "Minutes of silence before a keep-alive pulse (rustle's --minutes-of-silence).";
      };

      pulseSeconds = mkOption {
        type = types.ints.unsigned;
        default = 10;
        description = "Duration of each keep-alive pulse, in seconds (rustle's --pulse-duration).";
      };

      amplitude = mkOption {
        type = types.float;
        default = 0.05;
        description = "Keep-alive tone amplitude, 0.0-1.0 (sub-audible at low values).";
      };

      frequency = mkOption {
        type = types.ints.unsigned;
        default = 20;
        description = "Keep-alive tone frequency in Hz.";
      };

      threshold = mkOption {
        type = types.float;
        default = 0.001;
        description = "Monitor RMS above this counts as real sound (rustle's --threshold).";
      };

      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Log power/RMS/idle + key events to the journal, for tuning.";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.cec-tv-liveness = {
      Unit = {
        Description = "HDMI-CEC TV liveness (idle -> standby, input -> wake; rustle-style keep-alive)";
        After = ["pipewire.service"];
      };
      Service = {
        ExecStart = "${daemon}/bin/cec-tv-liveness";
        Environment = [
          "CEC_CTL=${pkgs.v4l-utils}/bin/cec-ctl"
          "PW_PLAY=${pkgs.pipewire}/bin/pw-play"
          "PW_RECORD=${pkgs.pipewire}/bin/pw-record"
          "UDEVADM=${pkgs.systemd}/bin/udevadm"
          "CEC_DEV=${cfg.device}"
          "OSD_NAME=${cfg.osdName}"
          "TV_LA=${toString cfg.tvLogicalAddress}"
          "AUDIO_LA=${toString cfg.audioSystemLogicalAddress}"
          "IDLE_SECONDS=${toString (cfg.idleMinutes * 60)}"
          "AUDIO_KEEPS_AWAKE=${
            if cfg.audioKeepsAwake
            then "1"
            else "0"
          }"
          "SINK=${
            if cfg.sink == null
            then ""
            else cfg.sink
          }"
          "KEEPALIVE=${
            if cfg.keepAwake.enable
            then "1"
            else "0"
          }"
          "SILENCE_SECONDS=${toString (cfg.keepAwake.silenceMinutes * 60)}"
          "PULSE_SECONDS=${toString cfg.keepAwake.pulseSeconds}"
          "TONE_FREQ=${toString cfg.keepAwake.frequency}"
          "TONE_AMP=${toString cfg.keepAwake.amplitude}"
          "THRESHOLD=${toString cfg.keepAwake.threshold}"
          "DEBUG=${
            if cfg.keepAwake.debug
            then "1"
            else "0"
          }"
        ];
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}

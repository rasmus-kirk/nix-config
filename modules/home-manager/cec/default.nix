{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.cec;

  # The box never powers off, so the TV follows activity instead of box power.
  # The daemon polls real TV power over CEC, so it wakes the TV however the TV went to standby.
  daemon = pkgs.writers.writePython3Bin "cec-tv-liveness" {
    libraries = [pkgs.python3Packages.evdev];
    flakeIgnore = ["E501" "E722" "E302" "E305" "E306" "W391" "E741" "E402"];
  } ''
    import array
    import math
    import os
    import re
    import select
    import signal
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

    # REF_PCT below 100 leaves headroom to detect a volume-up on the sink.
    VOL_RELAY = os.environ.get("VOL_RELAY", "0") == "1"
    REF_PCT = int(os.environ.get("REF_PCT", "75"))
    STEP_PCT = max(1, int(os.environ.get("STEP_PCT", "5")))
    PACTL = os.environ.get("PACTL", "pactl")

    POLL = 1.0
    RESCAN = 5.0
    RATE = 8000
    PWR_POLL = 5.0
    EV_KEY = 1
    KEY_SLEEP = 142
    # KEY_POWER is not handled because acpid owns the power button.
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
    g_tv_on = True
    g_phys = None
    g_last_ctrl = 0.0
    CTRL_TIMEOUT = 3.0
    udev_w = -1
    g_sleep_req = False

    def log(msg):
        if DEBUG:
            print("[cec] " + msg, flush=True)

    def note(msg):
        # Always logged, so callers must not pass typed key content.
        print("[cec] " + msg, flush=True)

    def on_sleep_signal(signum, frame):
        # configuration.nix replaces system suspend with SIGUSR1 to this daemon.
        global g_sleep_req
        g_sleep_req = True

    def cec(*args):
        # Address registration is a slow bus negotiation, so register once and
        # re-register only when an HPD event made cec-ctl report "unconfigured".
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
        out = ((p.stdout or "") + (p.stderr or "")).lower()
        if p.returncode != 0:
            return "rc=%d" % p.returncode
        if "nack" in out or "timed out" in out or "error" in out:
            return "nack/timeout"
        return "ok"

    def configure():
        cec()

    def cec_vol(ui_cmd, log_it):
        # The TV has no CEC volume control, so volume goes to the audio system.
        if log_it:
            note("%s pressed -> audio system" % ui_cmd)
        p = cec("--to", AUDIO_LA, "--user-control-pressed", "ui-cmd=" + ui_cmd,
                "--to", AUDIO_LA, "--user-control-released")
        if log_it:
            note("%s: %s" % (ui_cmd, cec_result(p)))

    def sink_state():
        if not SINK:
            return None
        try:
            v = subprocess.run([PACTL, "get-sink-volume", SINK],
                               capture_output=True, text=True, timeout=2).stdout
            m = subprocess.run([PACTL, "get-sink-mute", SINK],
                               capture_output=True, text=True, timeout=2).stdout
        except Exception:
            return None
        mm = re.search(r"(\d+)%", v)
        if not mm:
            return None
        return int(mm.group(1)), ("yes" in m)

    def set_sink(pct):
        try:
            subprocess.run([PACTL, "set-sink-volume", SINK, "%d%%" % pct],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=2)
        except Exception:
            pass

    def volume_monitor():
        # Steam controller volume keys only change the sink volume and never reach
        # evdev, so relay sink deviations from REF_PCT to the AVR and reset the sink.
        set_sink(REF_PCT)
        while True:
            time.sleep(0.3)
            st = sink_state()
            if st is None:
                continue
            vol, muted = st
            if muted:
                continue
            delta = vol - REF_PCT
            if abs(delta) >= 1:
                steps = max(1, int(round(abs(delta) / float(STEP_PCT))))
                cmd = "volume-up" if delta > 0 else "volume-down"
                for _ in range(steps):
                    cec_vol(cmd, False)
                note("controller volume %s x%d -> AVR (sink was %d%%)"
                     % (cmd, steps, vol))
                set_sink(REF_PCT)

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
        # The physical address is the operand of the System Audio Mode Request that wakes the AVR.
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
        # CEC cannot prevent AVR eco-standby, so wake the AVR again if the tone failed.
        # A "waking" log line means the keep-alive tone needs tuning.
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
        # Wake the main loop at once on input add/remove instead of after RESCAN.
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
        # Exclude nodes with letter keys, so the grab does not take typing from the desktop.
        try:
            caps = dev.capabilities().get(EV_KEY, [])
        except Exception:
            return False
        if KEY_VOLUMEUP not in caps and KEY_VOLUMEDOWN not in caps:
            return False
        return evdev.ecodes.KEY_A not in caps

    def refresh_devices(devs):
        # Grab the volume-key node, so the compositor does not also attenuate the sink feeding the AVR.
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
        # Valve vendor 0x28de. The logind uaccess ACL gives the session user access.
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
        # A powered-on controller streams hidraw reports in every input layout, so data flow means presence.
        # After a disconnect, a receiver hidraw fd stays readable at EOF, so empty reads retire the fd.
        global g_last_ctrl
        fds = {}
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
                            raise EOFError
                        got_data = True
                except BlockingIOError:
                    pass
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
        global wav_path, g_tv_on, udev_w, g_sleep_req
        signal.signal(signal.SIGUSR1, on_sleep_signal)
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
        if VOL_RELAY:
            threading.Thread(target=volume_monitor, daemon=True).start()
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
            sleep_pressed = False
            udev_event = False

            for fd in r:
                if fd == udev_r:
                    try:
                        os.read(udev_r, 4096)
                    except OSError:
                        pass
                    udev_event = True
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
                        # Ignore and never log all other keys.
                        if ev.code == KEY_SLEEP:
                            if ev.value == 1:
                                sleep_pressed = True
                        elif ev.code == KEY_VOLUMEUP:
                            cec_vol("volume-up", ev.value == 1)
                        elif ev.code == KEY_VOLUMEDOWN:
                            cec_vol("volume-down", ev.value == 1)
                        elif ev.code == KEY_MUTE and ev.value == 1:
                            cec_vol("mute", True)
                except OSError:
                    devs.pop(d.path, None)

            if g_sleep_req:
                g_sleep_req = False
                sleep_pressed = True

            if udev_event or now - last_rescan >= RESCAN:
                refresh_devices(devs)
                last_rescan = now

            present = (now - g_last_ctrl) < CTRL_TIMEOUT
            connect = present and not was_present
            was_present = present
            if connect and DEBUG:
                log("controller connect")

            real_audio = (now - g_last_audio) < 2.0
            if real_audio:
                last_sound = now

            if (real_audio and AUDIO_AWAKE) or present:
                last_activity = now

            # Audio never wakes the TV, so a manual standby holds while sound still plays.
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

    controllerVolume = {
      enable = mkEnableOption ''
        relaying volume changes on the TV sink to the AVR over CEC. The Steam
        controller's volume keys only reach the system/gamescope volume (never
        this daemon's evdev path), so the sink is held at referencePercent and
        any deviation is translated into CEC volume steps on the AVR, giving
        controller-driven AVR volume. Requires `sink` to be set'';
      referencePercent = mkOption {
        type = types.ints.between 1 99;
        default = 75;
        description = ''
          Percent the TV sink is held at (the AVR does the real attenuation).
          Must be <100 so a volume-UP (which raises the sink) is detectable.
        '';
      };
      stepPercent = mkOption {
        type = types.ints.positive;
        default = 5;
        description = "TV-sink % change that maps to one CEC volume step to the AVR.";
      };
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
          "VOL_RELAY=${
            if cfg.controllerVolume.enable
            then "1"
            else "0"
          }"
          "REF_PCT=${toString cfg.controllerVolume.referencePercent}"
          "STEP_PCT=${toString cfg.controllerVolume.stepPercent}"
          "PACTL=${pkgs.pulseaudio}/bin/pactl"
        ];
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}

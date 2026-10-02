use std::{
    env,
    f64::consts::PI,
    fs,
    io::{BufRead, BufReader},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use anyhow::Result;
use log::{debug, info};

use crate::{
    Config, KeepAwake,
    cec::Cec,
    util::{quiet, read_full, run, start, stdout},
};

const AUDIO_WINDOW: Duration = Duration::from_secs(2);
const PACTL_TIMEOUT: Duration = Duration::from_secs(2);
const RESTART_DELAY: Duration = Duration::from_secs(2);
const TONE_GRACE: Duration = Duration::from_secs(2);
const RATE: u32 = 8000;
const TONE_NAME: &str = "cec-keepalive";

/// The sink monitor state that the recorder thread writes and the main loop reads.
#[derive(Default)]
struct Monitor {
    last_heard: Option<Instant>,
    last_rms: f64,
    ignore_until: Option<Instant>,
}

/// Returns the pw-play and pw-record argument that pins a stream to the TV sink.
fn target(cfg: &Config) -> Option<String> {
    cfg.sink.as_ref().map(|sink| format!("--target={sink}"))
}

/// Returns the RMS of the signed 16-bit little-endian samples in buf, or None if buf has no
/// complete sample.
fn rms(buf: &[u8]) -> Option<f64> {
    let samples: Vec<f64> = buf
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&b| f64::from(i16::from_le_bytes(b)) / 32768.0)
        .collect();
    if samples.is_empty() {
        return None;
    }
    Some((samples.iter().map(|s| s * s).sum::<f64>() / samples.len() as f64).sqrt())
}

/// Records the TV sink monitor and stores the RMS of each one-second chunk. Sound at or above
/// threshold sets last_heard. Chunks are skipped until ignore_until, so the keep-alive tone does
/// not count as sound. Restarts pw-record if it exits.
fn record(cfg: &Config, monitor: &Mutex<Monitor>) {
    loop {
        let child = Command::new("pw-record")
            .args([
                "--raw",
                "--format=s16",
                &format!("--rate={RATE}"),
                "--channels=1",
            ])
            .args(target(cfg))
            .args(["-P", "stream.capture.sink=true", "-"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(mut child) = child {
            let mut out = child.stdout.take().unwrap();
            let mut buf = vec![0; RATE as usize * 2];
            while let Ok(n @ 1..) = read_full(&mut out, &mut buf) {
                let mut m = monitor.lock().unwrap();
                if m.ignore_until.is_some_and(|t| Instant::now() < t) {
                    continue;
                }
                let Some(rms) = rms(&buf[..n]) else {
                    continue;
                };
                m.last_rms = rms;
                if rms >= cfg.keep_awake.threshold {
                    m.last_heard = Some(Instant::now());
                }
            }
            let _ = child.kill();
            let _ = child.wait();
        }
        thread::sleep(RESTART_DELAY);
    }
}

/// Writes the keep-alive tone to a WAV file in XDG_RUNTIME_DIR and returns its path.
fn make_wav(keep: &KeepAwake) -> Result<PathBuf> {
    let n = RATE * keep.pulse_seconds.max(1);
    let amp = keep.amplitude * 32767.0;
    let step = 2.0 * PI * f64::from(keep.frequency) / f64::from(RATE);
    let dir = env::var_os("XDG_RUNTIME_DIR").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from);
    let path = dir.join("cec-keepalive.wav");
    let data_len = n * 2;
    let mut wav = Vec::with_capacity(44 + data_len as usize);
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + data_len).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&RATE.to_le_bytes());
    wav.extend_from_slice(&(RATE * 2).to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_len.to_le_bytes());
    for i in 0..n {
        let sample = (amp * (step * f64::from(i)).sin()) as i16;
        wav.extend_from_slice(&sample.to_le_bytes());
    }
    fs::write(&path, wav)?;
    Ok(path)
}

/// Returns the first number directly before a percent sign in text, or None if there is none.
fn percent(text: &str) -> Option<u32> {
    text.match_indices('%').find_map(|(i, _)| {
        let head = &text[..i];
        let digits = head.len() - head.trim_end_matches(|c: char| c.is_ascii_digit()).len();
        head[i - digits..].parse().ok()
    })
}

/// Returns the TV sink volume in percent and its mute state, or None if pactl fails.
fn sink_state(sink: &str) -> Option<(u32, bool)> {
    let vol = run(
        Command::new("pactl").args(["get-sink-volume", sink]),
        PACTL_TIMEOUT,
    )
    .ok()?;
    let mute = run(
        Command::new("pactl").args(["get-sink-mute", sink]),
        PACTL_TIMEOUT,
    )
    .ok()?;
    Some((percent(&stdout(&vol))?, stdout(&mute).contains("yes")))
}

/// Sets the TV sink volume to pct percent.
fn set_sink(sink: &str, pct: u32) {
    let _ = quiet(
        Command::new("pactl").args(["set-sink-volume", sink, &format!("{pct}%")]),
        PACTL_TIMEOUT,
    );
}

/// Sends the difference between the TV sink volume and referencePercent to the AVR as CEC
/// volume steps, then sets the sink back to referencePercent. A muted sink is ignored.
fn relay(cfg: &Config, cec: &Cec, sink: &str) {
    let relay = &cfg.controller_volume;
    let Some((vol, muted)) = sink_state(sink) else {
        return;
    };
    if muted || vol == relay.reference_percent {
        return;
    }
    let delta = i64::from(vol) - i64::from(relay.reference_percent);
    let steps =
        ((delta.abs() as f64 / f64::from(relay.step_percent)).round_ties_even() as u64).max(1);
    let cmd = if delta > 0 {
        "volume-up"
    } else {
        "volume-down"
    };
    for _ in 0..steps {
        cec.volume_key(cmd, false);
    }
    info!("controller volume {cmd} x{steps} -> AVR (sink was {vol}%)");
    set_sink(sink, relay.reference_percent);
}

/// Holds the TV sink at referencePercent. Runs relay on each sink change event from pactl
/// subscribe. The reset to referencePercent also makes an event, but it reads as no change, so
/// there is no feedback loop.
fn watch_volume(cfg: &Config, cec: &Cec, sink: &str) {
    set_sink(sink, cfg.controller_volume.reference_percent);
    loop {
        let child = Command::new("pactl")
            .arg("subscribe")
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(mut child) = child {
            relay(cfg, cec, sink);
            let out = BufReader::new(child.stdout.take().unwrap());
            for line in out.lines().map_while(Result::ok) {
                if line.contains("'change' on sink #") {
                    relay(cfg, cec, sink);
                }
            }
            let _ = child.wait();
        }
        thread::sleep(RESTART_DELAY);
    }
}

/// The TV sink. Records the sink monitor to detect sound, plays the keep-alive tone, and relays
/// sink volume changes to the AVR.
pub struct Audio {
    cfg: Arc<Config>,
    cec: Arc<Cec>,
    monitor: Arc<Mutex<Monitor>>,
    pub last_sound: Instant,
    wav_path: Option<PathBuf>,
    tone: Option<Child>,
}

impl Audio {
    /// Stores cfg and cec. Silence counts from the time the daemon starts.
    pub fn new(cfg: Arc<Config>, cec: Arc<Cec>) -> Self {
        Self {
            cfg,
            cec,
            monitor: Arc::default(),
            last_sound: Instant::now(),
            wav_path: None,
            tone: None,
        }
    }

    /// Returns true if the monitor heard sound in the last AUDIO_WINDOW.
    pub fn playing(&self, now: Instant) -> bool {
        let last_heard = self.monitor.lock().unwrap().last_heard;
        last_heard.is_some_and(|t| now - t < AUDIO_WINDOW)
    }

    /// Returns the RMS of the last monitor chunk.
    pub fn last_rms(&self) -> f64 {
        self.monitor.lock().unwrap().last_rms
    }

    /// Returns true while the keep-alive tone plays.
    fn pulsing(&mut self) -> bool {
        self.tone
            .as_mut()
            .is_some_and(|c| matches!(c.try_wait(), Ok(None)))
    }

    /// Starts the keep-alive tone on the TV sink, unless it already plays. The monitor ignores the
    /// sink until TONE_GRACE after the tone ends, so the tone and its tail do not count as sound.
    fn pulse(&mut self) {
        if self.pulsing() {
            return;
        }
        let Some(wav) = &self.wav_path else {
            return;
        };
        let child = Command::new("pw-play")
            .args(["-P", &format!("media.name={TONE_NAME}")])
            .args(target(&self.cfg))
            .arg(wav)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let Ok(child) = child else {
            return;
        };
        self.tone = Some(child);
        let ignore_until = Instant::now() + self.cfg.keep_awake.pulse() + TONE_GRACE;
        self.monitor.lock().unwrap().ignore_until = Some(ignore_until);
        debug!("keep-alive pulse");
    }

    /// Kills the keep-alive tone.
    fn stop_pulse(&mut self) {
        if let Some(mut tone) = self.tone.take() {
            let _ = tone.kill();
            let _ = tone.wait();
        }
    }

    /// While the TV is on, plays the keep-alive tone after silenceMinutes of silence. Stops the tone
    /// when the TV is off.
    pub fn keep_awake(&mut self, now: Instant, tv_on: bool) {
        let keep = &self.cfg.keep_awake;
        if self.playing(now) {
            self.last_sound = now;
        }
        if !(tv_on && keep.enable) {
            self.stop_pulse();
            return;
        }
        let silence = keep.silence();
        if !self.pulsing() && now - self.last_sound >= silence {
            self.pulse();
            self.last_sound = now;
        }
    }

    /// Writes the tone and starts the recorder if keepAwake is on. Starts the volume relay if
    /// controllerVolume is on.
    pub fn start(&mut self) {
        if self.cfg.keep_awake.enable {
            self.wav_path = make_wav(&self.cfg.keep_awake).ok();
            let (cfg, monitor) = (Arc::clone(&self.cfg), Arc::clone(&self.monitor));
            start(move || record(&cfg, &monitor));
        }
        if let (true, Some(sink)) = (self.cfg.controller_volume.enable, self.cfg.sink.clone()) {
            let (cfg, cec) = (Arc::clone(&self.cfg), Arc::clone(&self.cec));
            start(move || watch_volume(&cfg, &cec, &sink));
        }
    }
}

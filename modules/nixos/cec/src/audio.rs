use std::{
    f64::consts::PI,
    io::{BufRead, BufReader, Write},
    process::{Child, Command, Stdio},
    sync::{Arc, mpsc::Sender},
    thread,
    time::{Duration, Instant},
};

use log::{debug, info};

use crate::{
    Config, KeepAwake,
    cec::{Cec, UiCmd},
    daemon::Event,
    util::{read_full, run, start, stdout},
};

const AUDIO_WINDOW: Duration = Duration::from_secs(2);
const PACTL_TIMEOUT: Duration = Duration::from_secs(2);
const RESTART_DELAY: Duration = Duration::from_secs(2);
const TONE_GRACE: Duration = Duration::from_secs(2);
const RATE: u32 = 8000;
const TONE_NAME: &str = "cec-keepalive";

/// Returns the pw-play and pw-record arguments that select raw mono samples at RATE and pin the
/// stream to the TV sink.
fn stream_args(cfg: &Config) -> impl Iterator<Item = String> {
    ["--raw", "--format=s16", "--channels=1"]
        .map(String::from)
        .into_iter()
        .chain([format!("--rate={RATE}")])
        .chain(cfg.sink.as_ref().map(|sink| format!("--target={sink}")))
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

/// Records the TV sink monitor and sends the RMS of each one-second chunk as Rms. Restarts
/// pw-record if it exits.
fn record(cfg: &Config, tx: &Sender<Event>) {
    loop {
        let child = Command::new("pw-record")
            .args(stream_args(cfg))
            .args(["-P", "stream.capture.sink=true", "-"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(mut child) = child {
            let mut out = child.stdout.take().unwrap();
            let mut buf = vec![0; RATE as usize * 2];
            while let Ok(n @ 1..) = read_full(&mut out, &mut buf) {
                if let Some(rms) = rms(&buf[..n]) {
                    let _ = tx.send(Event::Rms(rms));
                }
            }
            let _ = child.kill();
            let _ = child.wait();
        }
        thread::sleep(RESTART_DELAY);
    }
}

/// Returns the keep-alive tone as signed 16-bit little-endian mono samples at RATE.
fn tone(keep: &KeepAwake) -> Vec<u8> {
    let amp = keep.amplitude * 32767.0;
    let step = 2.0 * PI * f64::from(keep.frequency) / f64::from(RATE);
    (0..RATE * keep.pulse_seconds.max(1))
        .flat_map(|i| ((amp * (step * f64::from(i)).sin()) as i16).to_le_bytes())
        .collect()
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
    let _ = run(
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
        UiCmd::VolumeUp
    } else {
        UiCmd::VolumeDown
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

/// The TV sink. Tracks sound on the sink monitor, plays the keep-alive tone, and relays sink
/// volume changes to the AVR.
pub struct Audio {
    cfg: Arc<Config>,
    cec: Arc<Cec>,
    tone: Arc<[u8]>,
    player: Option<Child>,
    last_heard: Option<Instant>,
    ignore_until: Option<Instant>,
    pub last_rms: f64,
    pub last_sound: Instant,
}

impl Audio {
    /// Stores cfg and cec and makes the tone. Silence counts from the time the daemon starts.
    pub fn new(cfg: Arc<Config>, cec: Arc<Cec>) -> Self {
        Self {
            tone: tone(&cfg.keep_awake).into(),
            cfg,
            cec,
            player: None,
            last_heard: None,
            ignore_until: None,
            last_rms: 0.0,
            last_sound: Instant::now(),
        }
    }

    /// Stores the RMS of a monitor chunk. Sound at or above threshold sets last_heard. Chunks are
    /// skipped until ignore_until, so the keep-alive tone does not count as sound.
    pub fn heard(&mut self, now: Instant, rms: f64) {
        if self.ignore_until.is_some_and(|t| now < t) {
            return;
        }
        self.last_rms = rms;
        if rms >= self.cfg.keep_awake.threshold {
            self.last_heard = Some(now);
        }
    }

    /// Returns true if the monitor heard sound in the last AUDIO_WINDOW.
    pub fn playing(&self, now: Instant) -> bool {
        self.last_heard.is_some_and(|t| now - t < AUDIO_WINDOW)
    }

    /// Returns true while the keep-alive tone plays.
    fn pulsing(&mut self) -> bool {
        self.player
            .as_mut()
            .is_some_and(|c| matches!(c.try_wait(), Ok(None)))
    }

    /// Starts the keep-alive tone on the TV sink, unless it already plays. A thread writes the
    /// samples to pw-play. The monitor ignores the sink until TONE_GRACE after the tone ends, so
    /// the tone and its tail do not count as sound.
    fn pulse(&mut self) {
        if self.pulsing() {
            return;
        }
        let child = Command::new("pw-play")
            .args(stream_args(&self.cfg))
            .args(["-P", &format!("media.name={TONE_NAME}"), "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut child) = child else {
            return;
        };
        let (mut stdin, tone) = (child.stdin.take().unwrap(), Arc::clone(&self.tone));
        start(move || {
            let _ = stdin.write_all(&tone);
        });
        self.player = Some(child);
        self.ignore_until = Some(Instant::now() + self.cfg.keep_awake.pulse() + TONE_GRACE);
        debug!("keep-alive pulse");
    }

    /// Kills the keep-alive tone.
    fn stop_pulse(&mut self) {
        if let Some(mut player) = self.player.take() {
            let _ = player.kill();
            let _ = player.wait();
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

    /// Starts the recorder if keepAwake is on. Starts the volume relay if controllerVolume is on.
    pub fn start(&self, tx: &Sender<Event>) {
        if self.cfg.keep_awake.enable {
            let (cfg, tx) = (Arc::clone(&self.cfg), tx.clone());
            start(move || record(&cfg, &tx));
        }
        if let (true, Some(sink)) = (self.cfg.controller_volume.enable, self.cfg.sink.clone()) {
            let (cfg, cec) = (Arc::clone(&self.cfg), Arc::clone(&self.cec));
            start(move || watch_volume(&cfg, &cec, &sink));
        }
    }
}

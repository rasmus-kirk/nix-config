use std::{
    cmp::Ordering,
    process::Stdio,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use anyhow::Result;
use log::{debug, info};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::Command,
    time::{sleep, timeout},
};

use crate::{
    Config,
    cec::{Cec, UiCmd},
    util::{run_command, stdout},
};

use audio_monitor::Monitor;

const RESTART_DELAY: Duration = Duration::from_secs(2);
const SAMPLE_INTERVAL: Duration = Duration::from_secs(3);
const RATE: u32 = 8000;

/// Samples the default sink monitor and tracks sound on it.
pub mod audio_monitor {
    use tokio::io::AsyncReadExt;

    use super::*;

    const AUDIO_WINDOW: Duration = Duration::from_secs(6);
    const TIMEOUT: Duration = Duration::from_secs(3);

    /// Returns the RMS of the signed 16-bit little-endian samples in buf.
    fn sound_level(buf: &[u8]) -> f64 {
        let samples = buf.as_chunks::<2>().0;
        let sum: f64 = samples
            .iter()
            .map(|&b| (f64::from(i16::from_le_bytes(b)) / 32768.0).powi(2))
            .sum();
        (sum / samples.len() as f64).sqrt()
    }

    /// Records one second of the sink monitor and returns its sound level. Returns None if
    /// pw-record fails or does not deliver the second within SAMPLE_TIMEOUT. Stops pw-record
    /// before it returns.
    pub async fn capture_audio() -> Option<f64> {
        let mut pw_record_bytes = Command::new("pw-record")
            .args(["--raw", "--format=s16", "--channels=1"])
            .arg(format!("--rate={RATE}"))
            .args(["-P", "stream.capture.sink=true", "-"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?
            .stdout?;
        let mut buf = vec![0; RATE as usize * 2];
        timeout(TIMEOUT, pw_record_bytes.read_exact(&mut buf))
            .await
            .ok()?
            .ok()?;
        Some(sound_level(&buf))
    }

    struct State {
        started: Instant,
        last_audio_detected: Option<Instant>,
        last_sound_level: f64,
    }

    /// A handle to the sound state. Clones share it.
    #[derive(Clone)]
    pub struct Monitor {
        config: Arc<Config>,
        state: Arc<Mutex<State>>,
    }

    impl Monitor {
        pub fn new(config: Arc<Config>) -> Self {
            Self {
                config,
                state: Arc::new(Mutex::new(State {
                    started: Instant::now(),
                    last_audio_detected: None,
                    last_sound_level: 0.0,
                })),
            }
        }

        /// Stores the sound level of a sample. Sound at or above threshold sets
        /// last_audio_detected.
        pub fn hear(&self, sound_level: f64) {
            let mut state = self.state.lock().unwrap();
            state.last_sound_level = sound_level;
            if sound_level >= self.config.keep_awake.threshold {
                state.last_audio_detected = Some(Instant::now());
            }
        }

        /// Returns the sound level of the last sample.
        pub fn last_sound_level(&self) -> f64 {
            self.state.lock().unwrap().last_sound_level
        }

        /// Returns true if the monitor heard sound in the last AUDIO_WINDOW.
        pub fn playing(&self, now: Instant) -> bool {
            self.state
                .lock()
                .unwrap()
                .last_audio_detected
                .is_some_and(|t| now - t < AUDIO_WINDOW)
        }

        /// Returns the time since the monitor last heard sound, or since start if it has not.
        pub fn silence(&self, now: Instant) -> Duration {
            let state = self.state.lock().unwrap();
            now - state.last_audio_detected.unwrap_or(state.started)
        }
    }
}

/// After silenceMinutes of silence while the TV is on, plays a sub-audible tone on the default sink, so
/// the speakers do not go to standby. The monitor takes no sample while the tone plays, so it never
/// hears the tone.
pub mod speaker_heartbeat {
    use super::*;

    /// Plays a sine tone on the default sink with SoX and returns when it ends. Gives up after the
    /// length of the tone plus RESTART_DELAY.
    async fn pulse(config: &Config) {
        let keep = &config.keep_awake;
        let mut play = Command::new("play");
        play.args(["-q", "-n", "synth"])
            .arg(keep.pulse_seconds.to_string())
            .args(["sine", &keep.frequency.to_string()])
            .args(["vol", &keep.amplitude.to_string()])
            .env("AUDIODRIVER", "pulseaudio")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        debug!("keep-alive pulse");
        let _ = timeout(keep.pulse() + RESTART_DELAY, play.status()).await;
    }

    /// Samples the monitor every SAMPLE_INTERVAL. When the TV is on and the silence, counted from
    /// the last sound or the last tone, reaches silenceMinutes, plays the tone. No sample runs
    /// while the tone plays, and the wait after it lets the tail die out, so the monitor never
    /// hears the tone.
    async fn run(config: &Config, cec: &Cec, monitor: &Monitor) {
        let keep = &config.keep_awake;
        let mut last_pulse = Instant::now();
        loop {
            if let Some(sound_level) = audio_monitor::capture_audio().await {
                monitor.hear(sound_level);
            }
            let quiet = monitor.silence(Instant::now()).min(last_pulse.elapsed());
            if cec.tv_on() && quiet >= keep.silence() {
                pulse(config).await;
                last_pulse = Instant::now();
            }
            sleep(SAMPLE_INTERVAL).await;
        }
    }

    /// Starts the monitor and the tone if keepAwake is on.
    pub fn start(config: Arc<Config>, cec: Arc<Cec>, monitor: Monitor) {
        if config.keep_awake.enable {
            tokio::spawn(async move { run(&config, &cec, &monitor).await });
        }
    }
}

/// Holds the default sink at referencePercent and relays its volume changes to the AVR.
pub mod volume_relay {
    use super::*;

    const SINK: &str = "@DEFAULT_SINK@";

    /// Returns the first number directly before a percent sign in text, or None if there is none.
    fn percent(text: &str) -> Option<u32> {
        text.match_indices('%').find_map(|(i, _)| {
            let head = &text[..i];
            let digits = head.len() - head.trim_end_matches(|c: char| c.is_ascii_digit()).len();
            head[i - digits..].parse().ok()
        })
    }

    /// Returns the default sink volume in percent, or None if pactl fails.
    async fn get_volume() -> Option<u32> {
        let volume = run_command(Command::new("pactl").args(["get-sink-volume", SINK]))
            .await
            .ok()?;
        percent(&stdout(&volume))
    }

    /// Sets the default sink volume to pct percent.
    async fn set_volume(pct: u32) -> Result<()> {
        run_command(Command::new("pactl").args(["set-sink-volume", SINK, &format!("{pct}%")]))
            .await?;
        Ok(())
    }

    /// Sends a change of the default sink volume from referencePercent to the AVR as one CEC volume
    /// step, then sets the sink back to referencePercent.
    async fn relay(config: &Config, cec: &Cec) {
        let relay = &config.controller_volume;
        let Some(vol) = get_volume().await else {
            return;
        };
        let cmd = match vol.cmp(&relay.reference_percent) {
            Ordering::Equal => return,
            Ordering::Greater => UiCmd::VolumeUp,
            Ordering::Less => UiCmd::VolumeDown,
        };
        cec.volume_key(cmd, false).await;
        info!("controller volume {cmd} -> AVR (sink was {vol}%)");
        let _ = set_volume(relay.reference_percent).await;
    }

    /// Holds the default sink at referencePercent. Runs relay on each sink change event from pactl
    /// subscribe. The reset to referencePercent also makes an event, but it reads as no change,
    /// so there is no feedback loop.
    async fn watch_volume(config: &Config, cec: &Cec) {
        let _ = set_volume(config.controller_volume.reference_percent).await;
        loop {
            let child = Command::new("pactl")
                .arg("subscribe")
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .spawn();
            if let Ok(mut child) = child {
                relay(config, cec).await;
                let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if line.contains("'change' on sink #") {
                        relay(config, cec).await;
                    }
                }
            }
            sleep(RESTART_DELAY).await;
        }
    }

    /// Starts the volume relay if controllerVolume is on.
    pub fn start(config: Arc<Config>, cec: Arc<Cec>) {
        if config.controller_volume.enable {
            tokio::spawn(async move { watch_volume(&config, &cec).await });
        }
    }
}

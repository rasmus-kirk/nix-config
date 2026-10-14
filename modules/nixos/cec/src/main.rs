mod audio;
mod cec;
mod cmd;
mod control_keys;
mod steam_controller;
mod tv;

use std::{fs, io::Write, path::PathBuf, sync::Arc, time::Duration};

use anyhow::{Context, Result};
use clap::Parser;
use log::LevelFilter;
use serde::Deserialize;
use tokio::sync::mpsc;

use crate::{
    audio::{audio_monitor::Monitor, speaker_heartbeat, volume_relay},
    cec::Cec,
    tv::Tv,
};

/// Keeps an HDMI-CEC TV in step with activity on an always-on box.
///
/// Runs the daemon with the settings in CONFIG, the kirk.cec options as JSON.
///
/// Puts the TV in standby after idleMinutes without activity. Activity is a sleep key press,
/// sound on the default sink, or a powered Steam controller that does not charge. The daemon polls the
/// real TV power state over CEC, so it also follows a standby by the TV timer or the TV remote.
///
/// The sleep key toggles the TV. SIGUSR1 has the same effect, so the system suspend action can
/// toggle the TV instead of suspending the box. A controller that connects wakes the TV. Sound
/// only keeps the TV awake, so a manual standby holds while audio plays. A controller that
/// charges on the puck is turned off.
///
/// Volume and mute keys go to the AVR over CEC. With keepAwake.enable, a sub-audible tone after
/// silenceMinutes of silence keeps the speakers out of standby. With controllerVolume.enable,
/// default sink volume changes become CEC volume steps to the AVR.
#[derive(Parser)]
#[command(version)]
struct Cli {
    /// JSON settings file.
    config: PathBuf,
}

/// The kirk.cec.keepAwake options.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct KeepAwake {
    pub enable: bool,
    pub silence_minutes: u64,
    pub pulse_seconds: u32,
    pub amplitude: f64,
    pub frequency: u32,
    pub threshold: f64,
}

impl KeepAwake {
    /// Returns silenceMinutes as a Duration.
    pub fn silence(&self) -> Duration {
        Duration::from_secs(self.silence_minutes * 60)
    }

    /// Returns pulseSeconds as a Duration.
    pub fn pulse(&self) -> Duration {
        Duration::from_secs(self.pulse_seconds.into())
    }
}

/// The kirk.cec.controllerVolume options.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ControllerVolume {
    pub enable: bool,
    pub reference_percent: u32,
}

/// The kirk.cec options, as the JSON file that Nix writes. Unknown or missing keys are an error.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Config {
    pub device: String,
    pub osd_name: String,
    pub idle_minutes: u64,
    pub tv_logical_address: u8,
    pub audio_system_logical_address: u8,
    pub audio_keeps_awake: bool,
    pub debug: bool,
    pub keep_awake: KeepAwake,
    pub controller_volume: ControllerVolume,
}

impl Config {
    /// Returns idleMinutes as a Duration.
    pub fn idle(&self) -> Duration {
        Duration::from_secs(self.idle_minutes * 60)
    }
}

/// Writes log records to stderr for the journal. Logs debug records only if debug is on. The
/// journal adds the time, so the records have none.
fn init_logger(debug: bool) {
    let level = if debug {
        LevelFilter::Debug
    } else {
        LevelFilter::Info
    };
    env_logger::Builder::new()
        .filter_level(level)
        .format(|buf, record| writeln!(buf, "[cec] {}", record.args()))
        .init();
}

/// Reads the settings in CONFIG, starts the parts and runs the TV rules.
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let text = fs::read_to_string(&cli.config)
        .with_context(|| format!("cannot read {}", cli.config.display()))?;
    let config: Config = serde_json::from_str(&text)
        .with_context(|| format!("cannot parse {}", cli.config.display()))?;
    init_logger(config.debug);
    let config = Arc::new(config);
    let cec = Arc::new(Cec::new(Arc::clone(&config)));
    let monitor = Monitor::new(Arc::clone(&config));
    let (tx, rx) = mpsc::unbounded_channel();
    cec.start().await;
    steam_controller::start(tx.clone());
    control_keys::start(Arc::clone(&cec), tx);
    speaker_heartbeat::start(Arc::clone(&config), Arc::clone(&cec), monitor.clone());
    volume_relay::start(Arc::clone(&config), Arc::clone(&cec));
    Tv::new(config, cec, monitor).run(rx).await
}

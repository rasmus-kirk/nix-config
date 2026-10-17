use std::{
    fmt,
    process::Output,
    sync::Arc,
    time::{Duration, Instant},
};

use log::info;
use tokio::{sync::Mutex, time::sleep};

use crate::{
    Config,
    cmd::{self, output, stdout},
};

const POWER_POLL: Duration = Duration::from_secs(5);
const VERIFY_POLL: Duration = Duration::from_secs(1);
const VERIFY_GRACE: Duration = Duration::from_secs(3);
const VERIFY_TIMEOUT: Duration = Duration::from_secs(15);
const ATTEMPTS: u32 = 3;
const TX_FAILURES: [&str; 8] = [
    "nack",
    "not acknowledged",
    "arbitration lost",
    "low drive",
    "timeout",
    "timed out",
    "max retries",
    "error",
];

/// A power command for the TV.
#[derive(Clone, Copy, PartialEq)]
pub enum TvAction {
    Standby,
    ImageViewOn,
}

impl TvAction {
    fn target(self) -> Power {
        match self {
            Self::Standby => Power::Standby,
            Self::ImageViewOn => Power::On,
        }
    }

    fn source(self) -> Power {
        match self {
            Self::Standby => Power::On,
            Self::ImageViewOn => Power::Standby,
        }
    }
}

impl fmt::Display for TvAction {
    /// Writes the cec-ctl name of the command.
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            Self::Standby => "standby",
            Self::ImageViewOn => "image-view-on",
        })
    }
}

#[derive(Clone, Copy, PartialEq)]
pub enum Power {
    On,
    Standby,
    Transition,
    NoReply,
}

impl fmt::Display for Power {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            Self::On => "on",
            Self::Standby => "standby",
            Self::Transition => "transition",
            Self::NoReply => "no reply",
        })
    }
}

/// A user control command for the audio system.
#[derive(Clone, Copy)]
pub enum UiCmd {
    VolumeUp,
    VolumeDown,
    Mute,
}

impl fmt::Display for UiCmd {
    /// Writes the cec-ctl name of the command.
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            Self::VolumeUp => "volume-up",
            Self::VolumeDown => "volume-down",
            Self::Mute => "mute",
        })
    }
}

/// Returns ok, no reply, the failed tx status or rc=N for a cec-ctl transmit, for the journal.
fn transmit_result(p: &Option<Output>) -> String {
    let Some(p) = p else {
        return "no reply".into();
    };
    if !p.status.success() {
        return match p.status.code() {
            Some(code) => format!("rc={code}"),
            None => "rc=signal".into(),
        };
    }
    let out = output(p);
    match TX_FAILURES.iter().find(|status| out.contains(*status)) {
        Some(status) => format!("failed ({status})"),
        None => "ok".into(),
    }
}

/// Returns the power state in the pwr-state field of cec-ctl output, or None if the field is
/// missing.
fn pwr_state(text: &str) -> Option<Power> {
    let (_, rest) = text.split_once("pwr-state:")?;
    match rest.split_whitespace().next()? {
        "in" => Some(Power::Transition),
        state if state.starts_with("on") => Some(Power::On),
        state if state.starts_with("standby") => Some(Power::Standby),
        _ => None,
    }
}

/// The CEC bus and the TV power state. All cec-ctl calls go through one lock, so the tasks do
/// not interleave on the adapter.
pub struct Cec {
    config: Arc<Config>,
    lock: Mutex<()>,
    power: std::sync::Mutex<Power>,
}

impl Cec {
    /// Stores config. The TV counts as no reply until the first power poll.
    pub fn new(config: Arc<Config>) -> Self {
        Self {
            config,
            lock: Mutex::new(()),
            power: std::sync::Mutex::new(Power::NoReply),
        }
    }

    /// Registers on the CEC bus and starts the TV power poll.
    pub async fn start(self: &Arc<Self>) {
        self.register().await;
        let cec = Arc::clone(self);
        tokio::spawn(async move { cec.poll_power().await });
    }

    /// Returns the last polled TV power state.
    pub fn power(&self) -> Power {
        *self.power.lock().unwrap()
    }

    pub fn tv_on(&self) -> bool {
        self.power() == Power::On
    }

    /// Runs cec-ctl on the adapter. Returns None if cec-ctl fails to start or times out.
    async fn cec_ctl(&self, args: &[&str]) -> Option<Output> {
        cmd::cec::cec_ctl(&self.config.device, args).await.ok()
    }

    /// Claims the playback logical address with osdName. The caller holds the lock.
    async fn playback(&self) -> Option<Output> {
        self.cec_ctl(&["--playback", "--osd-name", &self.config.osd_name])
            .await
    }

    /// Registers the playback logical address. Registration is a slow bus negotiation, so it runs
    /// once at start. The kernel keeps the address until an HPD event, for example a TV standby or
    /// wake.
    async fn register(&self) {
        let _guard = self.lock.lock().await;
        self.playback().await;
    }

    /// Sends a CEC message on the registered address. If cec-ctl reports that the adapter is
    /// unconfigured or sent from Unregistered after an HPD event, registers again and retries one
    /// time.
    pub async fn send(&self, args: &[&str]) -> Option<Output> {
        let _guard = self.lock.lock().await;
        let p = self.cec_ctl(args).await;
        if p.as_ref().is_some_and(|p| {
            let out = output(p);
            out.contains("unconfigured") || out.contains("from unregistered")
        }) {
            self.playback().await;
            return self.cec_ctl(args).await;
        }
        p
    }

    /// Returns the power state of the device at logical address la, or None if it does not reply.
    async fn power_status(&self, la: u8) -> Option<Power> {
        let p = self
            .send(&["--to", &la.to_string(), "--give-device-power-status"])
            .await?;
        pwr_state(&stdout(&p))
    }

    async fn poll_tv(&self) -> Power {
        let power = self
            .power_status(self.config.tv_logical_address)
            .await
            .unwrap_or(Power::NoReply);
        let old = std::mem::replace(&mut *self.power.lock().unwrap(), power);
        if old != power {
            info!("tv power {old} -> {power}");
        }
        power
    }

    /// Polls the real TV power state, so the power state follows a standby by the TV timer or the
    /// TV remote. The daemon does not wake an AVR that went to standby, so a manual AVR standby
    /// holds.
    async fn poll_power(&self) {
        loop {
            self.poll_tv().await;
            sleep(POWER_POLL).await;
        }
    }

    /// Sends action to the TV, logs reason and the result, and polls the TV until it reports the
    /// target state of action.
    pub async fn tv(&self, action: TvAction, reason: &str) {
        let la = self.config.tv_logical_address.to_string();
        let target = action.target();
        for attempt in 1..=ATTEMPTS {
            let try_label = match attempt {
                1 => String::new(),
                n => format!(" (attempt {n})"),
            };
            info!("{reason} -> {action}{try_label}");
            let p = self.send(&["--to", &la, &format!("--{action}")]).await;
            info!("{reason} -> {action}: {}", transmit_result(&p));
            let start = Instant::now();
            loop {
                sleep(VERIFY_POLL).await;
                let power = self.poll_tv().await;
                let elapsed = start.elapsed();
                if power == target {
                    info!(
                        "{reason} -> {action}: tv {power} after {}s",
                        elapsed.as_secs()
                    );
                    return;
                }
                if elapsed >= VERIFY_TIMEOUT
                    || (elapsed >= VERIFY_GRACE && power == action.source())
                {
                    break;
                }
            }
        }
        info!(
            "{reason} -> {action}: failed after {ATTEMPTS} attempts, tv {}",
            self.power()
        );
    }

    /// Sends ui_cmd to the audio system as a user control press and release. CEC volume goes to the
    /// AVR because the TV has no CEC control of its own speakers. Logs only when log_it is true, so
    /// autorepeat does not fill the journal.
    pub async fn volume_key(&self, ui_cmd: UiCmd, log_it: bool) {
        if log_it {
            info!("{ui_cmd} pressed -> audio system");
        }
        let la = self.config.audio_system_logical_address.to_string();
        let ui = format!("ui-cmd={ui_cmd}");
        let p = self
            .send(&[
                "--to",
                &la,
                "--user-control-pressed",
                &ui,
                "--to",
                &la,
                "--user-control-released",
            ])
            .await;
        if log_it {
            info!("{ui_cmd}: {}", transmit_result(&p));
        }
    }
}

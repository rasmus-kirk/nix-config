use std::{
    process::{Command, Output},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

use log::info;

use crate::{
    Config,
    util::{output, run, stdout},
};

const CEC_TIMEOUT: Duration = Duration::from_secs(4);
const POWER_POLL: Duration = Duration::from_secs(5);

/// Returns ok, no reply, nack/timeout or rc=N for a cec-ctl transmit, for the journal.
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
    if out.contains("nack") || out.contains("timed out") || out.contains("error") {
        return "nack/timeout".into();
    }
    "ok".into()
}

/// Returns true for on and false for off from the pwr-state field of cec-ctl output, or None if
/// the field is missing.
fn pwr_state(text: &str) -> Option<bool> {
    let (_, rest) = text.split_once("pwr-state:")?;
    let state = rest.split_whitespace().next()?;
    Some(state.starts_with("on"))
}

/// The CEC bus and the TV power state. All cec-ctl calls go through one lock, so the power poll
/// thread and the main loop do not interleave on the adapter.
pub struct Cec {
    cfg: Arc<Config>,
    lock: Mutex<()>,
    tv_on: AtomicBool,
}

impl Cec {
    /// Stores cfg. The TV counts as on until the first power poll replies.
    pub fn new(cfg: Arc<Config>) -> Self {
        Self {
            cfg,
            lock: Mutex::new(()),
            tv_on: AtomicBool::new(true),
        }
    }

    /// Returns the last known TV power state.
    pub fn tv_on(&self) -> bool {
        self.tv_on.load(Ordering::Relaxed)
    }

    /// Runs cec-ctl on the adapter. Returns None if cec-ctl fails to start or times out.
    fn cec_ctl(&self, args: &[&str]) -> Option<Output> {
        let mut cmd = Command::new("cec-ctl");
        cmd.args(["-d", &self.cfg.device, "-s"]).args(args);
        run(&mut cmd, CEC_TIMEOUT).ok()
    }

    /// Claims the playback logical address with osdName. The caller holds the lock.
    fn playback(&self) -> Option<Output> {
        self.cec_ctl(&["--playback", "--osd-name", &self.cfg.osd_name])
    }

    /// Registers the playback logical address. Registration is a slow bus negotiation, so it runs
    /// once at start. The kernel keeps the address until an HPD event, for example a TV standby or
    /// wake.
    pub fn register(&self) {
        let _guard = self.lock.lock().unwrap();
        self.playback();
    }

    /// Sends a CEC message on the registered address. If cec-ctl reports that the adapter is
    /// unconfigured after an HPD event, registers again and retries one time.
    pub fn send(&self, args: &[&str]) -> Option<Output> {
        let _guard = self.lock.lock().unwrap();
        let p = self.cec_ctl(args);
        if p.as_ref()
            .is_some_and(|p| output(p).contains("unconfigured"))
        {
            self.playback();
            return self.cec_ctl(args);
        }
        p
    }

    /// Returns true for on and false for off for the device at logical address la, or None if it
    /// does not reply.
    fn power_status(&self, la: u8) -> Option<bool> {
        let p = self.send(&["--to", &la.to_string(), "--give-device-power-status"])?;
        pwr_state(&stdout(&p))
    }

    /// Polls the real TV power state, so tv_on follows a standby by the TV timer or the TV remote.
    /// The daemon does not wake an AVR that went to standby, so a manual AVR standby holds.
    pub fn poll_power(&self) {
        loop {
            if let Some(on) = self.power_status(self.cfg.tv_logical_address) {
                self.tv_on.store(on, Ordering::Relaxed);
            }
            thread::sleep(POWER_POLL);
        }
    }

    /// Sends action to the TV, logs reason and the result, and records the new TV power state.
    pub fn tv(&self, action: &str, reason: &str) {
        info!("{reason} -> {action}");
        let la = self.cfg.tv_logical_address.to_string();
        let p = self.send(&["--to", &la, &format!("--{action}")]);
        info!("{reason} -> {action}: {}", transmit_result(&p));
        self.tv_on
            .store(action == "image-view-on", Ordering::Relaxed);
    }

    /// Sends ui_cmd to the audio system as a user control press and release. CEC volume goes to the
    /// AVR because the TV has no CEC control of its own speakers. Logs only when log_it is true, so
    /// autorepeat does not fill the journal.
    pub fn volume_key(&self, ui_cmd: &str, log_it: bool) {
        if log_it {
            info!("{ui_cmd} pressed -> audio system");
        }
        let la = self.cfg.audio_system_logical_address.to_string();
        let ui = format!("ui-cmd={ui_cmd}");
        let p = self.send(&[
            "--to",
            &la,
            "--user-control-pressed",
            &ui,
            "--to",
            &la,
            "--user-control-released",
        ]);
        if log_it {
            info!("{ui_cmd}: {}", transmit_result(&p));
        }
    }
}

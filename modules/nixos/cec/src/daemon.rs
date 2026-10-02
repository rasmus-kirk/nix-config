use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use log::debug;

use crate::{
    Config, audio::Audio, cec::Cec, control_keys::ControlKeys, steam_controller::SteamController,
    util::start,
};

const DEBUG_INTERVAL: Duration = Duration::from_secs(30);

/// Connects the parts and applies the TV rules once per tick.
pub struct Daemon {
    cfg: Arc<Config>,
    cec: Arc<Cec>,
    audio: Audio,
    controller: SteamController,
    keys: ControlKeys,
    last_activity: Instant,
    last_debug: Option<Instant>,
    sleep_requested: Arc<AtomicBool>,
}

impl Daemon {
    /// Builds the parts. Starts no threads and opens no devices.
    pub fn new(cfg: Arc<Config>) -> Self {
        let cec = Arc::new(Cec::new(Arc::clone(&cfg)));
        Self {
            audio: Audio::new(Arc::clone(&cfg), Arc::clone(&cec)),
            controller: SteamController::new(),
            keys: ControlKeys::new(Arc::clone(&cec)),
            last_activity: Instant::now(),
            last_debug: None,
            sleep_requested: Arc::default(),
            cfg,
            cec,
        }
    }

    /// The sleep key toggles the TV. A controller that connects wakes it. Idle time without a
    /// controller puts it in standby. Sound only keeps the TV awake and never wakes it, so a
    /// manual standby holds while audio plays.
    fn apply_rules(&mut self, now: Instant, sleep_pressed: bool, present: bool, connected: bool) {
        let cec = &self.cec;
        let tv_on = cec.tv_on();
        if (self.audio.playing(now) && self.cfg.audio_keeps_awake) || present {
            self.last_activity = now;
        }
        if sleep_pressed {
            self.last_activity = now;
            let was = if tv_on { "on" } else { "off" };
            let action = if tv_on { "standby" } else { "image-view-on" };
            cec.tv(action, &format!("sleep button (tv was {was})"));
        } else if connected && !tv_on {
            cec.tv("image-view-on", "controller connect");
        } else if tv_on && !present && now - self.last_activity >= self.cfg.idle() {
            cec.tv("standby", &format!("idle {}min", self.cfg.idle_minutes));
        }
    }

    /// Logs power, RMS, silence, idle and controller state every DEBUG_INTERVAL.
    fn debug_status(&mut self, now: Instant, present: bool) {
        if self.last_debug.is_some_and(|t| now - t < DEBUG_INTERVAL) {
            return;
        }
        self.last_debug = Some(now);
        debug!(
            "tv_on={} rms={:.4} silence={:.0}s idle={:.0}s present={present}",
            self.cec.tv_on(),
            self.audio.last_rms(),
            (now - self.audio.last_sound).as_secs_f64(),
            (now - self.last_activity).as_secs_f64(),
        );
    }

    /// Runs one pass of the main loop. A SIGUSR1 counts as a sleep key press, so the system
    /// suspend action can toggle the TV.
    fn tick(&mut self) {
        let sleep_pressed = self.keys.read() | self.sleep_requested.swap(false, Ordering::Relaxed);
        let now = Instant::now();
        let (present, connected) = self.controller.poll(now);
        if connected {
            debug!("controller connect");
        }
        self.apply_rules(now, sleep_pressed, present, connected);
        self.audio.keep_awake(now, self.cec.tv_on());
        self.debug_status(now, present);
    }

    /// Registers on the CEC bus, starts the threads and runs the main loop.
    pub fn run(mut self) -> Result<()> {
        signal_hook::flag::register(
            signal_hook::consts::SIGUSR1,
            Arc::clone(&self.sleep_requested),
        )
        .context("cannot handle SIGUSR1")?;
        self.cec.register();
        let cec = Arc::clone(&self.cec);
        start(move || cec.poll_power());
        self.controller.start();
        self.audio.start();
        self.keys.refresh();
        loop {
            self.tick();
        }
    }
}

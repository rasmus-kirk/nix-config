use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use log::debug;
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::mpsc,
    time::{MissedTickBehavior, interval},
};

use crate::{
    Config,
    audio::Audio,
    cec::{Cec, TvAction},
    control_keys, steam_controller,
};

const POLL: Duration = Duration::from_secs(1);
const CONTROLLER_TIMEOUT: Duration = Duration::from_secs(3);
const DEBUG_INTERVAL: Duration = Duration::from_secs(30);

/// An input to the main loop. All tasks send their events on one channel, so only the main
/// loop keeps timing state.
pub enum Event {
    Sleep,
    Rms(f64),
    ControllerSeen,
}

/// Connects the parts and applies the TV rules on each event, and at least once per POLL.
pub struct Daemon {
    cfg: Arc<Config>,
    cec: Arc<Cec>,
    audio: Audio,
    last_activity: Instant,
    last_seen: Option<Instant>,
    was_present: bool,
    last_debug: Option<Instant>,
}

impl Daemon {
    /// Builds the parts. Starts no tasks and opens no devices. No controller counts as present
    /// at start.
    pub fn new(cfg: Arc<Config>) -> Self {
        let cec = Arc::new(Cec::new(Arc::clone(&cfg)));
        Self {
            audio: Audio::new(Arc::clone(&cfg), Arc::clone(&cec)),
            last_activity: Instant::now(),
            last_seen: None,
            was_present: false,
            last_debug: None,
            cfg,
            cec,
        }
    }

    /// The sleep key toggles the TV. A controller that connects wakes it. Idle time without a
    /// controller puts it in standby. Sound only keeps the TV awake and never wakes it, so a
    /// manual standby holds while audio plays.
    async fn apply_rules(
        &mut self,
        now: Instant,
        sleep_pressed: bool,
        present: bool,
        connected: bool,
    ) {
        let cec = &self.cec;
        let tv_on = cec.tv_on();
        if (self.audio.playing(now) && self.cfg.audio_keeps_awake) || present {
            self.last_activity = now;
        }
        if sleep_pressed {
            self.last_activity = now;
            let was = if tv_on { "on" } else { "off" };
            let action = if tv_on {
                TvAction::Standby
            } else {
                TvAction::ImageViewOn
            };
            cec.tv(action, &format!("sleep button (tv was {was})"))
                .await;
        } else if connected && !tv_on {
            cec.tv(TvAction::ImageViewOn, "controller connect").await;
        } else if tv_on && !present && now - self.last_activity >= self.cfg.idle() {
            cec.tv(
                TvAction::Standby,
                &format!("idle {}min", self.cfg.idle_minutes),
            )
            .await;
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
            self.audio.last_rms,
            (now - self.audio.last_sound).as_secs_f64(),
            (now - self.last_activity).as_secs_f64(),
        );
    }

    /// Records event, then runs one pass of the TV rules. A controller is present while it sent
    /// data in the last CONTROLLER_TIMEOUT.
    async fn tick(&mut self, event: Option<Event>) {
        let now = Instant::now();
        let sleep_pressed = matches!(event, Some(Event::Sleep));
        match event {
            Some(Event::Rms(rms)) => self.audio.heard(now, rms),
            Some(Event::ControllerSeen) => self.last_seen = Some(now),
            Some(Event::Sleep) | None => {}
        }
        let present = self.last_seen.is_some_and(|t| now - t < CONTROLLER_TIMEOUT);
        let connected = present && !self.was_present;
        self.was_present = present;
        if connected {
            debug!("controller connect");
        }
        self.apply_rules(now, sleep_pressed, present, connected)
            .await;
        self.audio.keep_awake(now, self.cec.tv_on());
        self.debug_status(now, present);
    }

    /// Registers on the CEC bus, starts the tasks and runs the main loop. SIGUSR1 counts as a
    /// sleep key press, so the system suspend action can toggle the TV.
    pub async fn run(mut self) -> Result<()> {
        let (tx, mut rx) = mpsc::unbounded_channel();
        let mut sigusr1 = signal(SignalKind::user_defined1()).context("cannot handle SIGUSR1")?;
        self.cec.register().await;
        let cec = Arc::clone(&self.cec);
        tokio::spawn(async move { cec.poll_power().await });
        steam_controller::start(tx.clone());
        control_keys::start(Arc::clone(&self.cec), tx.clone());
        self.audio.start(&tx);
        let mut poll = interval(POLL);
        poll.set_missed_tick_behavior(MissedTickBehavior::Delay);
        loop {
            let event = tokio::select! {
                event = rx.recv() => event,
                _ = sigusr1.recv() => Some(Event::Sleep),
                _ = poll.tick() => None,
            };
            self.tick(event).await;
        }
    }
}

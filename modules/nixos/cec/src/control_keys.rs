use std::{
    collections::HashMap,
    fs, io,
    os::fd::AsRawFd,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use evdev::{Device, EventType, KeyCode};
use log::info;

use crate::{
    cec::Cec,
    util::{POLL, poll_ready},
};

const RESCAN: Duration = Duration::from_secs(5);

/// Returns the CEC user control command for a volume key, or None for any other key.
fn volume_cmd(code: KeyCode) -> Option<&'static str> {
    match code {
        KeyCode::KEY_VOLUMEUP => Some("volume-up"),
        KeyCode::KEY_VOLUMEDOWN => Some("volume-down"),
        _ => None,
    }
}

/// Returns true for an input node with volume keys and no letter keys. That is the Consumer Control
/// node, never a keyboard.
fn has_volume_keys(dev: &Device) -> bool {
    dev.supported_keys().is_some_and(|keys| {
        (keys.contains(KeyCode::KEY_VOLUMEUP) || keys.contains(KeyCode::KEY_VOLUMEDOWN))
            && !keys.contains(KeyCode::KEY_A)
    })
}

/// Returns the paths of the evdev nodes in /dev/input.
fn input_nodes() -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir("/dev/input") else {
        return Vec::new();
    };
    entries
        .filter_map(Result::ok)
        .filter(|e| e.file_name().to_string_lossy().starts_with("event"))
        .map(|e| e.path())
        .collect()
}

/// Handles the pending key events of dev. Forwards volume and mute to the AVR and returns true
/// if the sleep key was pressed. Ignores all other keys and does not log them.
fn read_keys(cec: &Cec, dev: &mut Device) -> io::Result<bool> {
    let mut sleep_pressed = false;
    for ev in dev.fetch_events()? {
        if ev.event_type() != EventType::KEY || !matches!(ev.value(), 1 | 2) {
            continue;
        }
        let pressed = ev.value() == 1;
        let code = KeyCode::new(ev.code());
        if code == KeyCode::KEY_SLEEP {
            sleep_pressed |= pressed;
        } else if let Some(cmd) = volume_cmd(code) {
            cec.volume_key(cmd, pressed);
        } else if code == KeyCode::KEY_MUTE && pressed {
            cec.volume_key("mute", true);
        }
    }
    Ok(sleep_pressed)
}

/// The sleep, volume and mute keys. The daemon can open only the input nodes that udev gives to
/// its group, the System Control and Consumer Control nodes, and those have no letter keys.
pub struct ControlKeys {
    cec: Arc<Cec>,
    devs: HashMap<PathBuf, Device>,
    last_rescan: Instant,
}

impl ControlKeys {
    /// Stores cec. Opens no nodes until refresh.
    pub fn new(cec: Arc<Cec>) -> Self {
        Self {
            cec,
            devs: HashMap::new(),
            last_rescan: Instant::now(),
        }
    }

    /// Opens each new input node once and drops nodes that are gone. Grabs the volume key node, so
    /// the compositor does not also change the sink. Closing the node releases the grab.
    pub fn refresh(&mut self) {
        self.last_rescan = Instant::now();
        let current = input_nodes();
        self.devs.retain(|path, _| current.contains(path));
        for path in current {
            if self.devs.contains_key(&path) {
                continue;
            }
            let Ok(mut dev) = Device::open(&path) else {
                continue;
            };
            if has_volume_keys(&dev) && dev.grab().is_ok() {
                info!(
                    "grabbed {} (volume keys -> AVR only)",
                    dev.name().unwrap_or("?")
                );
            }
            self.devs.insert(path, dev);
        }
    }

    /// Waits up to POLL for key events and handles them. Scans for input nodes every RESCAN.
    /// Returns true if the sleep key was pressed.
    pub fn read(&mut self) -> bool {
        let paths: Vec<PathBuf> = self.devs.keys().cloned().collect();
        let fds: Vec<_> = paths.iter().map(|p| self.devs[p].as_raw_fd()).collect();
        let mut sleep_pressed = false;
        for i in poll_ready(&fds, POLL) {
            let dev = self.devs.get_mut(&paths[i]).unwrap();
            match read_keys(&self.cec, dev) {
                Ok(pressed) => sleep_pressed |= pressed,
                Err(_) => {
                    self.devs.remove(&paths[i]);
                }
            }
        }
        if self.last_rescan.elapsed() >= RESCAN {
            self.refresh();
        }
        sleep_pressed
    }
}

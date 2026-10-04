use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::{Arc, mpsc::Sender},
    time::Duration,
};

use evdev::{Device, EventType, KeyCode};
use log::info;

use crate::{
    cec::{Cec, UiCmd},
    daemon::Event,
    util::{self, watch_nodes},
};

const RESCAN: Duration = Duration::from_secs(5);

/// Returns the CEC user control command for a volume key, or None for any other key.
fn volume_cmd(code: KeyCode) -> Option<UiCmd> {
    match code {
        KeyCode::KEY_VOLUMEUP => Some(UiCmd::VolumeUp),
        KeyCode::KEY_VOLUMEDOWN => Some(UiCmd::VolumeDown),
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

/// Opens the input node at path and handles its key events until the node fails. Grabs the volume
/// key node, so the compositor does not also change the sink. Closing the node releases the grab.
/// Forwards volume and mute to the AVR and sends Sleep on a sleep key press. Ignores all other
/// keys and does not log them.
fn read_keys(path: &Path, cec: &Cec, tx: &Sender<Event>) -> io::Result<()> {
    let mut dev = Device::open(path)?;
    if has_volume_keys(&dev) && dev.grab().is_ok() {
        info!(
            "grabbed {} (volume keys -> AVR only)",
            dev.name().unwrap_or("?")
        );
    }
    loop {
        for ev in dev.fetch_events()? {
            if ev.event_type() != EventType::KEY || !matches!(ev.value(), 1 | 2) {
                continue;
            }
            let pressed = ev.value() == 1;
            let code = KeyCode::new(ev.code());
            if code == KeyCode::KEY_SLEEP && pressed {
                let _ = tx.send(Event::Sleep);
            } else if let Some(cmd) = volume_cmd(code) {
                cec.volume_key(cmd, pressed);
            } else if code == KeyCode::KEY_MUTE && pressed {
                cec.volume_key(UiCmd::Mute, true);
            }
        }
    }
}

/// Watches the sleep, volume and mute keys. The daemon can open only the input nodes that udev
/// gives to its group, the System Control and Consumer Control nodes, and those have no letter
/// keys.
pub fn start(cec: Arc<Cec>, tx: Sender<Event>) {
    util::start(move || {
        watch_nodes(RESCAN, input_nodes, move |path| {
            let _ = read_keys(path, &cec, &tx);
        })
    });
}

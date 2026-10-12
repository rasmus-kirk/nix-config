use std::{
    collections::HashMap,
    fs, io,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use evdev::{Device, EventType, KeyCode};
use log::info;
use tokio::{sync::mpsc::UnboundedSender, task::JoinHandle, time::sleep};

use crate::{
    cec::{Cec, UiCmd},
    tv::Event,
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
async fn read_keys(path: &Path, cec: &Cec, tx: &UnboundedSender<Event>) -> io::Result<()> {
    let mut dev = Device::open(path)?;
    if has_volume_keys(&dev) && dev.grab().is_ok() {
        info!(
            "grabbed {} (volume keys -> AVR only)",
            dev.name().unwrap_or("?")
        );
    }
    let mut events = dev.into_event_stream()?;
    loop {
        let ev = events.next_event().await?;
        if ev.event_type() != EventType::KEY || !matches!(ev.value(), 1 | 2) {
            continue;
        }
        let pressed = ev.value() == 1;
        let code = KeyCode::new(ev.code());
        if code == KeyCode::KEY_SLEEP && pressed {
            let _ = tx.send(Event::Sleep);
        } else if let Some(cmd) = volume_cmd(code) {
            cec.volume_key(cmd, pressed).await;
        } else if code == KeyCode::KEY_MUTE && pressed {
            cec.volume_key(UiCmd::Mute, true).await;
        }
    }
}

/// Watches the sleep, volume and mute keys. The daemon can open only the input nodes that udev
/// gives to its group, the System Control and Consumer Control nodes, and those have no letter
/// keys. Every RESCAN, reads each node that no task reads. A node is read again only after its read
/// returns, for example at EOF or after the device is gone.
pub fn start(cec: Arc<Cec>, tx: UnboundedSender<Event>) {
    tokio::spawn(async move {
        let mut open: HashMap<PathBuf, JoinHandle<()>> = HashMap::new();
        loop {
            open.retain(|_, task| !task.is_finished());
            for path in input_nodes() {
                open.entry(path.clone()).or_insert_with(|| {
                    let (cec, tx) = (Arc::clone(&cec), tx.clone());
                    tokio::spawn(async move {
                        let _ = read_keys(&path, &cec, &tx).await;
                    })
                });
            }
            sleep(RESCAN).await;
        }
    });
}

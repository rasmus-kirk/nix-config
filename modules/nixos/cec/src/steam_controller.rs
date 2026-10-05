use std::{
    fs::{self, File},
    io::{self, Read},
    path::{Path, PathBuf},
    sync::mpsc::Sender,
    time::{Duration, Instant},
};

use crate::{
    daemon::Event,
    util::{self, watch_nodes},
};

const CONTROLLER_SCAN: Duration = Duration::from_secs(2);
const SEEN_INTERVAL: Duration = Duration::from_secs(1);
const VALVE_VENDOR: &str = "28DE";

/// Returns the hidraw nodes of Valve devices, which are the Steam controller and its receiver.
/// logind gives the session user access to them, so no extra group is necessary.
fn controller_hidraws() -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir("/sys/class/hidraw") else {
        return Vec::new();
    };
    entries
        .filter_map(Result::ok)
        .filter(|e| {
            fs::read_to_string(e.path().join("device/uevent"))
                .is_ok_and(|uevent| uevent.to_uppercase().contains(VALVE_VENDOR))
        })
        .map(|e| PathBuf::from("/dev").join(e.file_name()))
        .collect()
}

/// Reads the Valve hidraw node at path until EOF or an error. Sends ControllerSeen at most once
/// per SEEN_INTERVAL while the node delivers data. Only a non-empty read counts. After a
/// controller disconnects, the receiver leaves one node at EOF, so the read returns and the node
/// is opened again on the next scan.
fn read_reports(path: &Path, tx: &Sender<Event>) -> io::Result<()> {
    let mut file = File::open(path)?;
    let mut buf = [0; 256];
    let mut last_sent: Option<Instant> = None;
    while file.read(&mut buf)? > 0 {
        if last_sent.is_none_or(|t| t.elapsed() >= SEEN_INTERVAL) {
            last_sent = Some(Instant::now());
            let _ = tx.send(Event::ControllerSeen);
        }
    }
    Ok(())
}

/// Watches Steam controller presence. Steam reads the controller over hidraw, so evdev never sees
/// its input. A controller sends hidraw reports for as long as it is on, in every input layout, so
/// data on a Valve hidraw node means a controller is on.
pub fn start(tx: Sender<Event>) {
    util::start(move || {
        watch_nodes(CONTROLLER_SCAN, controller_hidraws, move |path| {
            let _ = read_reports(path, &tx);
        })
    });
}

use std::{
    collections::HashMap,
    fs::{self, File, OpenOptions},
    io::{ErrorKind, Read},
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::PathBuf,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use crate::util::{POLL, poll_ready};

const CONTROLLER_SCAN: Duration = Duration::from_secs(2);
const CONTROLLER_TIMEOUT: Duration = Duration::from_secs(3);
const CONTROLLER_SLEEP: Duration = Duration::from_millis(200);
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

/// Reads file until it has no more data. Returns whether a read delivered data, and whether file
/// is at EOF or failed and must be closed.
fn drain(file: &mut File) -> (bool, bool) {
    let mut buf = [0; 256];
    let mut got_data = false;
    loop {
        match file.read(&mut buf) {
            Ok(0) => return (got_data, true),
            Ok(_) => got_data = true,
            Err(e) if e.kind() == ErrorKind::WouldBlock => return (got_data, false),
            Err(_) => return (got_data, true),
        }
    }
}

/// Sets last_seen when a Valve hidraw node delivers data. Only a non-empty read counts. After a
/// controller disconnects, the receiver leaves one node at EOF that poll() reports as
/// readable forever, so a node at EOF is closed and opened again on the next scan.
fn watch(last_seen: &Mutex<Option<Instant>>) {
    let mut files: HashMap<PathBuf, File> = HashMap::new();
    let mut last_scan: Option<Instant> = None;
    loop {
        if last_scan.is_none_or(|t| t.elapsed() >= CONTROLLER_SCAN) {
            last_scan = Some(Instant::now());
            for path in controller_hidraws() {
                if files.contains_key(&path) {
                    continue;
                }
                let file = OpenOptions::new()
                    .read(true)
                    .custom_flags(libc::O_NONBLOCK)
                    .open(&path);
                if let Ok(file) = file {
                    files.insert(path, file);
                }
            }
        }
        if files.is_empty() {
            thread::sleep(CONTROLLER_SCAN);
            continue;
        }
        let paths: Vec<PathBuf> = files.keys().cloned().collect();
        let fds: Vec<_> = paths.iter().map(|p| files[p].as_raw_fd()).collect();
        let mut got_data = false;
        for i in poll_ready(&fds, POLL) {
            let (data, eof) = drain(files.get_mut(&paths[i]).unwrap());
            got_data |= data;
            if eof {
                files.remove(&paths[i]);
            }
        }
        if got_data {
            *last_seen.lock().unwrap() = Some(Instant::now());
        }
        thread::sleep(CONTROLLER_SLEEP);
    }
}

/// Steam controller presence. Steam reads the controller over hidraw, so evdev never sees its
/// input. A controller sends hidraw reports for as long as it is on, in every input layout, so
/// data on a Valve hidraw node means a controller is on.
pub struct SteamController {
    last_seen: Arc<Mutex<Option<Instant>>>,
    was_present: bool,
}

impl SteamController {
    /// No controller counts as present at start.
    pub fn new() -> Self {
        Self {
            last_seen: Arc::default(),
            was_present: false,
        }
    }

    /// Runs watch in a thread.
    pub fn start(&self) {
        let last_seen = Arc::clone(&self.last_seen);
        thread::spawn(move || watch(&last_seen));
    }

    /// Returns whether a controller is present, and whether it connected since the last poll. Only
    /// the main loop calls this.
    pub fn poll(&mut self, now: Instant) -> (bool, bool) {
        let last_seen = *self.last_seen.lock().unwrap();
        let present = last_seen.is_some_and(|t| now - t < CONTROLLER_TIMEOUT);
        let connected = present && !self.was_present;
        self.was_present = present;
        (present, connected)
    }
}

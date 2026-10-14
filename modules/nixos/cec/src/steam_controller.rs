use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read},
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::{Path, PathBuf},
    time::Duration,
};

use log::{info, warn};
use nix::fcntl::OFlag;
use tokio::{
    io::{Interest, unix::AsyncFd},
    sync::mpsc::UnboundedSender,
    time::{sleep, timeout},
};

use crate::tv::Event;

const CONTROLLER_SCAN: Duration = Duration::from_secs(2);
const READ_WINDOW: Duration = Duration::from_millis(200);
const VALVE_VENDOR: &str = "28DE";
const BATTERY_REPORT_ID: u8 = 0x43;
const BATTERY_REPORT_LEN: usize = 15;

enum ControllerStatus {
    Discharging,
    Charging,
    Full,
}

impl ControllerStatus {
    fn parse(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != BATTERY_REPORT_LEN || bytes[0] != BATTERY_REPORT_ID {
            return None;
        }
        match bytes[1] {
            1 => Some(Self::Discharging),
            2 => Some(Self::Charging),
            4 => Some(Self::Full),
            _ => None,
        }
    }
}

struct Controller {
    path: PathBuf,
    hidraw_file: AsyncFd<File>,
}

impl Controller {
    fn new(path: &Path) -> io::Result<Self> {
        Ok(Self {
            path: path.to_owned(),
            hidraw_file: AsyncFd::new(
                OpenOptions::new()
                    .read(true)
                    .write(true)
                    .custom_flags(OFlag::O_NONBLOCK.bits())
                    .open(path)?,
            )?,
        })
    }

    async fn step(&mut self) -> io::Result<Option<Event>> {
        let mut buf = [0; 64];
        let n = self
            .hidraw_file
            .async_io(Interest::READABLE, |mut file| file.read(&mut buf))
            .await?;
        if n == 0 {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        match ControllerStatus::parse(&buf[..n]) {
            Some(ControllerStatus::Charging | ControllerStatus::Full) => {
                self.turn_off();
                Ok(None)
            }
            Some(ControllerStatus::Discharging) | None => Ok(Some(Event::ControllerSeen)),
        }
    }

    fn turn_off(&self) {
        nix::ioctl_readwrite_buf!(hidiocsfeature, b'H', 0x06, u8);

        let mut report = [0; 64];
        report[..7].copy_from_slice(b"\x01\x9f\x04off!");
        let fd = self.hidraw_file.as_raw_fd();
        match unsafe { hidiocsfeature(fd, &mut report) } {
            Ok(_) => info!("{}: charging controller turned off", self.path.display()),
            Err(e) => warn!("{}: cannot turn off controller: {e}", self.path.display()),
        }
    }
}

/// Returns the hidraw nodes of Valve devices, which are the Steam controller and its receiver.
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

/// Watches Steam controller presence. Steam reads the controller over hidraw, so evdev never sees
/// its input. A controller sends hidraw reports for as long as it is on, in every input layout, so
/// data on a Valve hidraw node means a controller is on. A controller that charges is turned off.
///
/// Every scan, each node is opened and read for one report, for at most READ_WINDOW. A
/// disconnected controller leaves its receiver node at EOF, which ends the read at once.
pub fn start(tx: UnboundedSender<Event>) {
    tokio::spawn(async move {
        loop {
            for path in controller_hidraws() {
                let Ok(mut controller) = Controller::new(&path) else {
                    continue;
                };
                if let Ok(Ok(Some(event))) = timeout(READ_WINDOW, controller.step()).await {
                    let _ = tx.send(event);
                }
            }
            sleep(CONTROLLER_SCAN).await;
        }
    });
}

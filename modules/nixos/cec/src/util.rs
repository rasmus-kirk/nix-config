use std::{
    collections::HashSet,
    io::{self, Read},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Result, bail};

/// Runs cmd and returns the completed process with stdout and stderr. Kills cmd and returns an
/// error if it fails to start or does not exit within timeout.
pub fn run(cmd: &mut Command, timeout: Duration) -> Result<Output> {
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let deadline = Instant::now() + timeout;
    while child.try_wait()?.is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!("timed out after {timeout:?}");
        }
        thread::sleep(Duration::from_millis(10));
    }
    Ok(child.wait_with_output()?)
}

/// Returns the stdout of p as text.
pub fn stdout(p: &Output) -> String {
    String::from_utf8_lossy(&p.stdout).into_owned()
}

/// Returns the stdout and stderr of p as one lowercase string.
pub fn output(p: &Output) -> String {
    format!("{}{}", stdout(p), String::from_utf8_lossy(&p.stderr)).to_lowercase()
}

/// Reads from r until buf is full or r is at EOF, and returns the number of bytes read.
pub fn read_full(r: &mut impl Read, buf: &mut [u8]) -> io::Result<usize> {
    let mut n = 0;
    while n < buf.len() {
        match r.read(&mut buf[n..])? {
            0 => break,
            k => n += k,
        }
    }
    Ok(n)
}

/// Runs f in a detached thread.
pub fn start(f: impl FnOnce() + Send + 'static) {
    thread::spawn(f);
}

/// Every interval, starts a thread that runs read for each node that list returns and no thread
/// reads. A node is read again only after its read returns, for example at EOF or after the
/// device is gone.
pub fn watch_nodes(
    interval: Duration,
    list: fn() -> Vec<PathBuf>,
    read: impl Fn(&Path) + Send + Sync + 'static,
) {
    let read = Arc::new(read);
    let open = Arc::new(Mutex::new(HashSet::new()));
    loop {
        for path in list() {
            if !open.lock().unwrap().insert(path.clone()) {
                continue;
            }
            let (read, open) = (Arc::clone(&read), Arc::clone(&open));
            start(move || {
                read(&path);
                open.lock().unwrap().remove(&path);
            });
        }
        thread::sleep(interval);
    }
}

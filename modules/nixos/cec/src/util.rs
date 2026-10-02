use std::{
    io::{self, Read},
    os::fd::RawFd,
    process::{Child, Command, ExitStatus, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Result, bail};

pub const POLL: Duration = Duration::from_secs(1);

/// Waits up to timeout for child to exit and returns its status. Kills child and returns an error
/// if it does not exit in time.
fn wait(child: &mut Child, timeout: Duration) -> Result<ExitStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(status);
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!("timed out after {timeout:?}");
        }
        thread::sleep(Duration::from_millis(10));
    }
}

/// Runs cmd and returns the completed process with stdout and stderr. Returns an error if cmd
/// fails to start or does not exit within timeout.
pub fn run(cmd: &mut Command, timeout: Duration) -> Result<Output> {
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let status = wait(&mut child, timeout)?;
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    if let Some(mut out) = child.stdout.take() {
        out.read_to_end(&mut stdout)?;
    }
    if let Some(mut err) = child.stderr.take() {
        err.read_to_end(&mut stderr)?;
    }
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

/// Runs cmd and discards its output. Returns an error if cmd fails to start or does not exit
/// within timeout.
pub fn quiet(cmd: &mut Command, timeout: Duration) -> Result<ExitStatus> {
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    wait(&mut child, timeout)
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

/// Waits up to timeout for one of fds to be ready and returns the indices of the ready fds. A
/// node with an error or hangup counts as ready, so its read reports the error. Returns no
/// indices on timeout or if poll fails, for example on a signal.
pub fn poll_ready(fds: &[RawFd], timeout: Duration) -> Vec<usize> {
    let mut pfds: Vec<libc::pollfd> = fds
        .iter()
        .map(|&fd| libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        })
        .collect();
    let ms = timeout.as_millis() as libc::c_int;
    if unsafe { libc::poll(pfds.as_mut_ptr(), pfds.len() as libc::nfds_t, ms) } <= 0 {
        return Vec::new();
    }
    pfds.iter()
        .enumerate()
        .filter(|(_, p)| p.revents != 0)
        .map(|(i, _)| i)
        .collect()
}

/// Runs f in a detached thread.
pub fn start(f: impl FnOnce() + Send + 'static) {
    thread::spawn(f);
}

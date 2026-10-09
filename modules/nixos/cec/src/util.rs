use std::{
    collections::HashMap,
    io,
    path::PathBuf,
    process::{Output, Stdio},
    time::Duration,
};

use anyhow::{Result, bail};
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    process::Command,
    task::JoinHandle,
    time::sleep,
};

/// Runs cmd and returns the completed process with stdout and stderr. Kills cmd and returns an
/// error if it fails to start or does not exit within timeout.
pub async fn run(cmd: &mut Command, timeout: Duration) -> Result<Output> {
    let child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()?;
    match tokio::time::timeout(timeout, child.wait_with_output()).await {
        Ok(output) => Ok(output?),
        Err(_) => bail!("timed out after {timeout:?}"),
    }
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
pub async fn read_full(r: &mut (impl AsyncRead + Unpin), buf: &mut [u8]) -> io::Result<usize> {
    let mut n = 0;
    while n < buf.len() {
        match r.read(&mut buf[n..]).await? {
            0 => break,
            k => n += k,
        }
    }
    Ok(n)
}

/// Every interval, starts a task that runs read for each node that list returns and no task
/// reads. A node is read again only after its read returns, for example at EOF or after the
/// device is gone.
pub async fn watch_nodes<F>(
    interval: Duration,
    list: fn() -> Vec<PathBuf>,
    read: impl Fn(PathBuf) -> F,
) where
    F: Future<Output = ()> + Send + 'static,
{
    let mut open: HashMap<PathBuf, JoinHandle<()>> = HashMap::new();
    loop {
        open.retain(|_, task| !task.is_finished());
        for path in list() {
            open.entry(path.clone())
                .or_insert_with(|| tokio::spawn(read(path)));
        }
        sleep(interval).await;
    }
}

use std::{
    process::{Output, Stdio},
    time::Duration,
};

use anyhow::{Result, bail};
use tokio::process::Command;

const TIMEOUT: Duration = Duration::from_secs(4);

async fn run(cmd: &mut Command) -> Result<Output> {
    let child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()?;
    match tokio::time::timeout(TIMEOUT, child.wait_with_output()).await {
        Ok(output) => Ok(output?),
        Err(_) => bail!("timed out after {TIMEOUT:?}"),
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

pub mod audio {
    use std::process::Stdio;

    use anyhow::Result;
    use tokio::{io::AsyncReadExt, process::Command, time::timeout};

    use super::{TIMEOUT, run};

    const RATE: u32 = 8000;

    fn sound_level(buf: &[u8]) -> f64 {
        let samples = buf.as_chunks::<2>().0;
        let sum: f64 = samples
            .iter()
            .map(|&b| (f64::from(i16::from_le_bytes(b)) / 32768.0).powi(2))
            .sum();
        (sum / samples.len() as f64).sqrt()
    }

    pub async fn capture_audio() -> Option<f64> {
        let mut child = Command::new("pw-record")
            .args(["--raw", "--format=s16", "--channels=1"])
            .arg(format!("--rate={RATE}"))
            .args(["-P", "stream.capture.sink=true", "-"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?;
        let mut stdout = child.stdout.take()?;
        let mut buf = vec![0; RATE as usize * 2];
        timeout(TIMEOUT, stdout.read_exact(&mut buf))
            .await
            .ok()?
            .ok()?;
        Some(sound_level(&buf))
    }

    pub async fn play(seconds: u32, frequency: u32, amplitude: f64) -> Result<()> {
        run(Command::new("play")
            .args(["-q", "-n", "synth"])
            .arg(seconds.to_string())
            .args(["sine", &frequency.to_string()])
            .args(["vol", &amplitude.to_string()])
            .env("AUDIODRIVER", "pulseaudio"))
        .await?;
        Ok(())
    }

    fn percent(text: &str) -> Option<u32> {
        text.match_indices('%').find_map(|(i, _)| {
            let head = &text[..i];
            let digits = head.len() - head.trim_end_matches(|c: char| c.is_ascii_digit()).len();
            head[i - digits..].parse().ok()
        })
    }

    pub async fn get_default_sink() -> Option<String> {
        let out = run(Command::new("pactl").arg("get-default-sink"))
            .await
            .ok()?;
        Some(super::stdout(&out).trim().to_owned())
    }

    pub async fn get_sink_volume(sink: &str) -> Option<u32> {
        let out = run(Command::new("pactl").args(["get-sink-volume", sink]))
            .await
            .ok()?;
        percent(&super::stdout(&out))
    }

    pub async fn set_sink_volume(sink: &str, pct: u32) -> Result<()> {
        run(Command::new("pactl").args(["set-sink-volume", sink, &format!("{pct}%")])).await?;
        Ok(())
    }

    pub fn subscribe() -> std::io::Result<tokio::process::Child> {
        Command::new("pactl")
            .arg("subscribe")
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
    }
}

pub mod cec {
    use std::process::Output;

    use anyhow::Result;
    use tokio::process::Command;

    use super::run;

    pub async fn cec_ctl(device: &str, args: &[&str]) -> Result<Output> {
        run(Command::new("cec-ctl")
            .args(["-d", device, "-s"])
            .args(args))
        .await
    }
}

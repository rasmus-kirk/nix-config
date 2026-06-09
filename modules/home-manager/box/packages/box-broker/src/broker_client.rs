//! In-box request-submission helpers. Used by every `box-broker`
//! subcommand that needs human approval: builds an envelope, drops it
//! atomically into `${brokerRoot}/request/`, waits for the host TUI to
//! ack within ~5s, then polls for the final response. The host-side
//! `box-approver` binary doesn't use any of this — it lives entirely
//! over here in the lib so both binaries can share the envelope
//! types.

use crate::types::{ClientContext, RequestEnvelope, Response, ResponseStatus};
use anyhow::{Context, Result};
use serde_json::{json, Value};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process;
use std::time::Duration;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio::time::{sleep, Instant};

/// Default request timeout: 30 minutes. The TUI is human-paced.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(1800);

/// Default broker root inside the box. Bind-mounted to the same path on
/// the host so the TUI sees the files.
pub const DEFAULT_BROKER_ROOT: &str = "/tmp/box-broker";

/// Outcome of a brokered request — maps 1:1 to the box-broker process
/// exit code (and matches the legacy exit codes that the in-box bash
/// scripts emitted, so callers that grep stderr still work).
#[derive(Debug)]
pub enum Outcome {
    Ok(Value),
    Rejected(String),
    SignFailed(String),
    DispatchFailed(String),
    Abandoned(String),
    Timeout(String),
    TuiNotRunning,
}

impl Outcome {
    pub fn exit_code(&self) -> i32 {
        match self {
            Self::Ok(_) => 0,
            Self::Rejected(_) => 10,
            Self::SignFailed(_) | Self::DispatchFailed(_) => 11,
            Self::TuiNotRunning => 12,
            Self::Abandoned(_) => 13,
            Self::Timeout(_) => 14,
        }
    }

    /// Write a human-readable summary to stderr (for failure cases) and
    /// `.result` to stdout (for success). Then exit with `exit_code()`.
    /// Convenience for CLI subcommands.
    pub fn finish_and_exit(self) -> ! {
        match &self {
            Self::Ok(result) => {
                println!("{}", serde_json::to_string(result).unwrap_or_default());
            }
            Self::Rejected(msg)
            | Self::SignFailed(msg)
            | Self::DispatchFailed(msg)
            | Self::Abandoned(msg)
            | Self::Timeout(msg) => {
                eprintln!("{msg}");
            }
            Self::TuiNotRunning => {
                eprintln!(
                    "box-broker: TUI not running on host (no ack within 5s). \
                     Start `box-approver` on the host and retry."
                );
            }
        }
        process::exit(self.exit_code());
    }
}

/// Atomic-write + poll request submission. The hot path for every
/// subcommand that goes through the TUI.
pub async fn submit_and_wait(
    op: &str,
    payload: Value,
    summary: Option<String>,
    timeout: Duration,
    broker_root: &Path,
) -> Result<Outcome> {
    let request_dir = broker_root.join("request");
    let response_dir = broker_root.join("response");
    if !request_dir.is_dir() {
        return Ok(Outcome::TuiNotRunning);
    }

    let pid = process::id();
    let nanos = chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0);
    let id = format!("{nanos}.{pid}");
    let now = chrono::Utc::now().to_rfc3339();
    let envelope = RequestEnvelope {
        v: 1,
        request_id: id.clone(),
        requested_at: now.clone(),
        op: op.to_string(),
        payload,
        summary: summary.filter(|s| !s.is_empty()),
        client_context: Some(ClientContext {
            cwd: std::env::current_dir()
                .ok()
                .and_then(|p| p.to_str().map(str::to_string))
                .unwrap_or_default(),
            agent_pid: pid,
            session_id: std::env::var("BOX_SESSION_ID").ok(),
            started_at: now,
        }),
    };

    let staging = request_dir.join(format!(".staging.{id}"));
    let final_ = request_dir.join(format!("{id}.json"));
    let mut f = fs::File::create(&staging)
        .await
        .with_context(|| format!("creating {}", staging.display()))?;
    f.write_all(&serde_json::to_vec(&envelope)?)
        .await
        .context("writing request envelope")?;
    f.flush().await.context("flushing request envelope")?;
    drop(f);
    fs::rename(&staging, &final_)
        .await
        .context("atomic-renaming request envelope into place")?;

    // 5s ack window. If the host TUI is running it will write the ack
    // file basically immediately (one inotify hop + one fs::write).
    let ack_path = response_dir.join(format!("{id}.ack"));
    let ack_deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < ack_deadline {
        if fs::try_exists(&ack_path).await.unwrap_or(false) {
            break;
        }
        sleep(Duration::from_millis(250)).await;
    }
    if !fs::try_exists(&ack_path).await.unwrap_or(false) {
        return Ok(Outcome::TuiNotRunning);
    }

    // Now wait for the final response. Timeout is the configured one.
    let resp_path = response_dir.join(format!("{id}.json"));
    let resp_deadline = Instant::now() + timeout;
    let response_bytes = loop {
        match fs::read(&resp_path).await {
            Ok(b) => break b,
            Err(e) if e.kind() == ErrorKind::NotFound => {}
            Err(e) => {
                return Err(e).with_context(|| format!("reading {}", resp_path.display()))?;
            }
        }
        if Instant::now() >= resp_deadline {
            return Ok(Outcome::Timeout(format!(
                "no decision within {}s",
                timeout.as_secs()
            )));
        }
        sleep(Duration::from_millis(500)).await;
    };
    let response: Response =
        serde_json::from_slice(&response_bytes).context("parsing response JSON")?;
    Ok(match response.status {
        ResponseStatus::Ok => Outcome::Ok(response.result.unwrap_or(Value::Null)),
        ResponseStatus::Rejected => {
            Outcome::Rejected(response.detail.unwrap_or_else(|| "rejected".into()))
        }
        ResponseStatus::SignFailed => {
            Outcome::SignFailed(response.detail.unwrap_or_else(|| "sign failed".into()))
        }
        ResponseStatus::DispatchFailed => {
            Outcome::DispatchFailed(response.detail.unwrap_or_else(|| "dispatch failed".into()))
        }
        ResponseStatus::Abandoned => {
            Outcome::Abandoned(response.detail.unwrap_or_else(|| "abandoned".into()))
        }
    })
}

/// Fire-and-forget drop of an `agent-event` JSON file. Used by
/// `box-broker agent-event` and `box-broker agent-hook`. No response,
/// no polling — the TUI's bottom pane consumes the file via inotify.
pub async fn drop_agent_event(
    broker_root: &Path,
    event: &str,
    claude_session_id: Option<&str>,
) -> Result<()> {
    let dir = broker_root.join("agent-events");
    if !dir.is_dir() {
        // Broker not mounted (box launched without the broker
        // bind-mounts). Silent no-op — same as the legacy bash script.
        return Ok(());
    }
    let pid = process::id();
    let nanos = chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0);
    let id = format!("{nanos}.{pid}");
    let session_id = std::env::var("BOX_SESSION_ID").unwrap_or_else(|_| "unknown".into());
    let now = chrono::Utc::now().to_rfc3339();
    let cwd = std::env::current_dir()
        .ok()
        .and_then(|p| p.to_str().map(str::to_string))
        .unwrap_or_default();
    let payload = json!({
        "event": event,
        "session_id": session_id,
        "claude_session_id": claude_session_id.unwrap_or(""),
        "cwd": cwd,
        "ts": now,
    });
    let staging = dir.join(format!(".staging.{id}"));
    let final_ = dir.join(format!("{id}.json"));
    fs::write(&staging, serde_json::to_vec(&payload)?)
        .await
        .with_context(|| format!("writing {}", staging.display()))?;
    fs::rename(&staging, &final_)
        .await
        .context("renaming agent-event into place")?;
    Ok(())
}

/// Resolve the broker root from the BOX_BROKER_ROOT env var or fall
/// back to the default. Mirrors how the host approver does it.
pub fn broker_root_from_env() -> PathBuf {
    std::env::var("BOX_BROKER_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_BROKER_ROOT))
}

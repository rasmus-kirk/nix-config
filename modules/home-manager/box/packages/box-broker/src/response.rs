use crate::config::Config;
use crate::types::{Response, ResponseStatus};
use anyhow::{Context, Result};
use serde_json::Value;
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// Write a final response file for a request. Atomic via .staging rename.
pub async fn write_response(cfg: &Config, request_id: &str, response: &Response) -> Result<()> {
    let dir = cfg.response_dir();
    fs::create_dir_all(&dir)
        .await
        .with_context(|| format!("creating {}", dir.display()))?;
    let final_path = dir.join(format!("{request_id}.json"));
    let staging_path = dir.join(format!(".staging.{request_id}"));
    let mut f = fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&staging_path)
        .await
        .context("opening staging response")?;
    let bytes = serde_json::to_vec(response).context("encoding response")?;
    f.write_all(&bytes).await.context("writing response")?;
    f.flush().await.context("flushing response")?;
    fs::rename(&staging_path, &final_path)
        .await
        .context("renaming response into place")?;
    Ok(())
}

/// Write a small ack file so the in-box client can distinguish "TUI is
/// running but the user hasn't decided yet" from "TUI not running at all".
pub async fn write_ack(cfg: &Config, request_id: &str) -> Result<()> {
    let dir = cfg.response_dir();
    fs::create_dir_all(&dir)
        .await
        .with_context(|| format!("creating {}", dir.display()))?;
    let path = dir.join(format!("{request_id}.ack"));
    fs::write(&path, b"acked\n").await.context("writing ack")?;
    Ok(())
}

pub fn ok_response(result: Value) -> Response {
    Response {
        status: ResponseStatus::Ok,
        result: Some(result),
        detail: None,
    }
}

pub fn rejected_response() -> Response {
    Response {
        status: ResponseStatus::Rejected,
        result: None,
        detail: Some("user rejected via TUI".into()),
    }
}

pub fn dispatch_failed_response(detail: String) -> Response {
    Response {
        status: ResponseStatus::DispatchFailed,
        result: None,
        detail: Some(detail),
    }
}

pub fn abandoned_response(detail: String) -> Response {
    Response {
        status: ResponseStatus::Abandoned,
        result: None,
        detail: Some(detail),
    }
}

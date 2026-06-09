use crate::types::ResponseStatus;
use anyhow::{Context, Result};
use serde::Serialize;
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;

#[derive(Debug, Clone)]
pub struct AuditLog {
    path: PathBuf,
}

#[derive(Debug, Serialize)]
pub struct AuditEntry<'a> {
    pub recorded_at: String,
    pub request_id: &'a str,
    pub op: &'a str,
    pub status: ResponseStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canonical_sha256: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<&'a serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<&'a str>,
}

impl AuditLog {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    pub async fn append(&self, entry: &AuditEntry<'_>) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("creating audit dir {}", parent.display()))?;
        }
        let mut line = serde_json::to_vec(entry).context("encoding audit entry")?;
        line.push(b'\n');
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
            .await
            .with_context(|| format!("opening audit log {}", self.path.display()))?;
        f.write_all(&line).await.context("writing audit line")?;
        f.flush().await.context("flushing audit log")?;
        Ok(())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(bytes);
    hex::encode(h.finalize())
}

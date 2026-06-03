use crate::types::{RequestEnvelope, SignedEnvelope};
use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use std::path::Path;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

pub struct SignOutput {
    pub signed: SignedEnvelope,
    pub canonical_bytes: Vec<u8>,
    pub signature: String,
}

/// Build the canonical bytes (JSON, sorted keys) for an approved envelope
/// and sign them with `ssh-keygen -Y sign` using `key_path` (which is the
/// YubiKey-backed SK private blob — `ssh-keygen` will prompt for a touch).
///
/// Returns the signed envelope (envelope + approved_at), the canonical
/// bytes that were signed, and the SSH signature.
pub async fn sign_envelope(envelope: &RequestEnvelope, key_path: &Path) -> Result<SignOutput> {
    let signed = SignedEnvelope {
        envelope: envelope.clone(),
        approved_at: Utc::now().to_rfc3339(),
    };
    let canonical_bytes = canonicalize(&signed)?;
    let signature = run_ssh_sign(key_path, &canonical_bytes).await?;
    Ok(SignOutput {
        signed,
        canonical_bytes,
        signature,
    })
}

/// Serialise the signed envelope deterministically. Uses serde_json with
/// recursive key sorting so the produced bytes are stable across runs and
/// match what the verifier sees.
///
/// This is JCS-style (RFC 8785) for the structure we use — we don't need
/// full RFC 8785 number-normalisation since payloads are agent-produced
/// JSON without exotic numerics.
pub fn canonicalize(signed: &SignedEnvelope) -> Result<Vec<u8>> {
    let value = serde_json::to_value(signed).context("encoding signed envelope")?;
    let mut out = Vec::with_capacity(512);
    write_canonical(&mut out, &value)?;
    Ok(out)
}

fn write_canonical(out: &mut Vec<u8>, v: &serde_json::Value) -> Result<()> {
    use serde_json::Value;
    match v {
        Value::Null => out.extend_from_slice(b"null"),
        Value::Bool(true) => out.extend_from_slice(b"true"),
        Value::Bool(false) => out.extend_from_slice(b"false"),
        Value::Number(n) => out.extend_from_slice(n.to_string().as_bytes()),
        Value::String(s) => {
            let escaped = serde_json::to_string(s).context("escaping string")?;
            out.extend_from_slice(escaped.as_bytes());
        }
        Value::Array(items) => {
            out.push(b'[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                write_canonical(out, item)?;
            }
            out.push(b']');
        }
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            out.push(b'{');
            for (i, k) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                let key = serde_json::to_string(k).context("escaping key")?;
                out.extend_from_slice(key.as_bytes());
                out.push(b':');
                write_canonical(out, &map[*k])?;
            }
            out.push(b'}');
        }
    }
    Ok(())
}

async fn run_ssh_sign(key_path: &Path, canonical_bytes: &[u8]) -> Result<String> {
    let mut child = Command::new("ssh-keygen")
        .args(["-Y", "sign", "-f"])
        .arg(key_path)
        .args(["-n", "approval"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .context("spawning ssh-keygen -Y sign")?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(canonical_bytes)
            .await
            .context("writing canonical bytes to ssh-keygen stdin")?;
        stdin.shutdown().await.ok();
    }

    let out = child.wait_with_output().await.context("ssh-keygen wait")?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(anyhow!(
            "ssh-keygen exited {}: {}",
            out.status,
            if stderr.is_empty() { "no stderr" } else { &stderr }
        ));
    }
    let sig = String::from_utf8(out.stdout).context("ssh-keygen output not UTF-8")?;
    if !sig.contains("BEGIN SSH SIGNATURE") {
        return Err(anyhow!("ssh-keygen output is not an SSH signature"));
    }
    Ok(sig)
}

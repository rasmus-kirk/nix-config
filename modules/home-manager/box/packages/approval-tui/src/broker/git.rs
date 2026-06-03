use super::{Broker, BrokerFuture};
use crate::types::RequestEnvelope;
use anyhow::{bail, Context, Result};
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::PathBuf;
use tokio::process::Command;

/// Common payload for git push / pull / fetch. The wrapper script in the
/// box captures the box's cwd, full argv (after the wrapper's selection),
/// plus a snapshot of useful local state for the TUI summary.
#[derive(Debug, Deserialize)]
struct GitNetPayload {
    cwd: PathBuf,
    argv: Vec<String>,
    #[serde(default)]
    current_branch: Option<String>,
    #[serde(default)]
    head_sha: Option<String>,
    #[serde(default)]
    upstream_state: Option<String>,
    #[serde(default)]
    signing_status: Option<String>,
}

/// Argv elements that change git's global behaviour (config, helper paths,
/// upload/receive pack); refused before invoking git.
const FORBIDDEN_PREFIXES: &[&str] = &["-c", "--exec-path", "--upload-pack", "--receive-pack", "--config-env"];

fn sanitize_argv(argv: &[String]) -> Result<()> {
    for a in argv {
        if a.contains('\0') {
            bail!("argv element contains NUL: {a:?}");
        }
        for bad in FORBIDDEN_PREFIXES {
            if a == bad || a.starts_with(&format!("{bad}=")) {
                bail!("forbidden git flag: {a}");
            }
        }
    }
    Ok(())
}

async fn run_git(cwd: &PathBuf, argv: &[String]) -> Result<Value> {
    let out = Command::new("git")
        .current_dir(cwd)
        .args(argv)
        .output()
        .await
        .with_context(|| format!("spawning git in {}", cwd.display()))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    if !out.status.success() {
        bail!(
            "git {} failed ({}): {}",
            argv.join(" "),
            out.status,
            stderr.trim()
        );
    }
    Ok(json!({
        "stdout": stdout,
        "stderr": stderr,
        "argv": argv,
    }))
}

/// Refuse to push if any commit in `@{u}..HEAD` is unsigned. Runs on the
/// host, where signature verification is authoritative (the host's git
/// config wires up `gpg.format=ssh` + `allowedSignersFile` via kirk.git).
/// Skipped if there's no upstream (git log will exit non-zero) — in that
/// case the underlying `git push` will surface its own error.
async fn assert_all_pushed_commits_signed(cwd: &PathBuf) -> Result<()> {
    let out = Command::new("git")
        .current_dir(cwd)
        .args(["log", "@{u}..HEAD", "--format=%H %G?"])
        .output()
        .await
        .with_context(|| format!("checking signing status in {}", cwd.display()))?;
    if !out.status.success() {
        // No upstream / other config issue — defer to git push for the
        // real error message rather than guessing.
        return Ok(());
    }
    let s = String::from_utf8_lossy(&out.stdout);
    let mut unsigned: Vec<String> = Vec::new();
    for line in s.lines() {
        let mut parts = line.split_whitespace();
        let sha = parts.next().unwrap_or("");
        let status = parts.next().unwrap_or("");
        if sha.is_empty() {
            continue;
        }
        match status {
            // Good signature, or signed with a key we don't have keyed in.
            "G" | "U" | "X" | "Y" => {}
            "N" => unsigned.push(sha.to_string()),
            "B" => bail!("refusing push: {sha} has a bad signature"),
            "E" => bail!("refusing push: {sha} signature can't be verified (missing key)"),
            other => bail!("refusing push: {sha} has unknown signing status `{other}`"),
        }
    }
    if !unsigned.is_empty() {
        let preview: Vec<String> = unsigned
            .iter()
            .take(5)
            .map(|s| s.chars().take(8).collect::<String>())
            .collect();
        let suffix = if unsigned.len() > preview.len() {
            format!(" (+ {} more)", unsigned.len() - preview.len())
        } else {
            String::new()
        };
        bail!(
            "refusing to push: {} unsigned commit(s) in @{{u}}..HEAD: {}{}. \
             Run `git-batch-sign` in the box first.",
            unsigned.len(),
            preview.join(", "),
            suffix,
        );
    }
    Ok(())
}

// ─── push ──────────────────────────────────────────────────────────────────

pub struct GitPush;

impl Broker for GitPush {
    fn op_id(&self) -> &'static str {
        "git.push"
    }
    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: GitNetPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "git push (malformed payload)".into(),
        };
        let mut out = format!(
            "git {} (from {})",
            p.argv.join(" "),
            p.cwd.display()
        );
        if let Some(branch) = &p.current_branch {
            out.push_str(&format!("\nbranch: {branch}"));
        }
        if let Some(state) = &p.upstream_state {
            out.push_str(&format!("\nahead of @{{u}}:\n{state}"));
        }
        if let Some(sig) = &p.signing_status {
            out.push_str(&format!("\nsigning: {sig}"));
        }
        out
    }
    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: GitNetPayload =
                serde_json::from_value(env.payload.clone()).context("decoding push payload")?;
            sanitize_argv(&p.argv)?;
            for arg in &p.argv {
                if arg == "--mirror" || arg == "--all" {
                    bail!("push flag rejected: {arg}");
                }
            }
            assert_all_pushed_commits_signed(&p.cwd).await?;
            run_git(&p.cwd, &p.argv).await
        })
    }
}

// ─── pull / fetch ──────────────────────────────────────────────────────────

pub struct GitPull;

impl Broker for GitPull {
    fn op_id(&self) -> &'static str {
        "git.pull"
    }
    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: GitNetPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "git pull (malformed payload)".into(),
        };
        format!("git {} (in {})", p.argv.join(" "), p.cwd.display())
    }
    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: GitNetPayload =
                serde_json::from_value(env.payload.clone()).context("decoding pull payload")?;
            sanitize_argv(&p.argv)?;
            run_git(&p.cwd, &p.argv).await
        })
    }
}

pub struct GitFetch;

impl Broker for GitFetch {
    fn op_id(&self) -> &'static str {
        "git.fetch"
    }
    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: GitNetPayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "git fetch (malformed payload)".into(),
        };
        format!("git {} (in {})", p.argv.join(" "), p.cwd.display())
    }
    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: GitNetPayload =
                serde_json::from_value(env.payload.clone()).context("decoding fetch payload")?;
            sanitize_argv(&p.argv)?;
            run_git(&p.cwd, &p.argv).await
        })
    }
}

// ─── sign-range ────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct GitSignRangePayload {
    cwd: PathBuf,
    #[serde(default)]
    base: Option<String>,
    #[serde(default)]
    head_sha: Option<String>,
    #[serde(default)]
    commit_list: Option<String>,
}

pub struct GitSignRange;

impl Broker for GitSignRange {
    fn op_id(&self) -> &'static str {
        "git.sign-range"
    }
    fn fallback_summary(&self, env: &RequestEnvelope) -> String {
        let p: GitSignRangePayload = match serde_json::from_value(env.payload.clone()) {
            Ok(p) => p,
            Err(_) => return "git-sign-range (malformed payload)".into(),
        };
        let base = p.base.unwrap_or_else(|| "@{u}".into());
        let mut s = format!("Sign commits in {} from {} to HEAD", p.cwd.display(), base);
        if let Some(list) = p.commit_list.as_deref() {
            s.push_str("\n\n");
            s.push_str(list);
        }
        s
    }
    fn dispatch<'a>(&'a self, env: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let p: GitSignRangePayload = serde_json::from_value(env.payload.clone())
                .context("decoding sign-range payload")?;
            let mut cmd = Command::new("git-sign-range");
            cmd.current_dir(&p.cwd);
            if let Some(base) = p.base.as_deref() {
                cmd.arg(base);
            }
            let out = cmd
                .output()
                .await
                .with_context(|| format!("spawning git-sign-range in {}", p.cwd.display()))?;
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            if !out.status.success() {
                bail!(
                    "git-sign-range failed ({}): {}",
                    out.status,
                    stderr.trim()
                );
            }
            Ok(json!({
                "stdout": stdout,
                "stderr": stderr,
            }))
        })
    }
}

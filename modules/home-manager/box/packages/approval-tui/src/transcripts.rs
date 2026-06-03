use anyhow::{Context, Result};
use notify::event::{CreateKind, EventKind, ModifyKind};
use notify::{recommended_watcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use tokio::sync::mpsc;

/// Emitted when the transcript watcher sees a new `agent-name` line in a
/// `~/.claude/projects/<slug>/<uuid>.jsonl` file. The `claude_session_id`
/// is the file's basename (without `.jsonl`); the TUI cross-references it
/// against AgentEntry.claude_session_id to find the right agent.
#[derive(Debug)]
pub enum TranscriptEvent {
    AgentName {
        claude_session_id: String,
        name: String,
    },
    Error(String),
}

/// Recursively watch `~/.claude/projects/` for jsonl modifications. On
/// any change to a `*.jsonl` file, grep it for `"type":"agent-name"`
/// lines, take the last one's `agentName`, and emit. The whole-file
/// re-grep is cheap (these files have at most a handful of agent-name
/// entries and aren't huge).
pub fn spawn(projects_dir: &Path) -> Result<mpsc::UnboundedReceiver<TranscriptEvent>> {
    let (tx, rx) = mpsc::unbounded_channel();
    let dir = projects_dir.to_path_buf();
    if !dir.exists() {
        // Not running under Claude Code yet — just don't watch. The TUI
        // can survive without transcript-derived names (cwd basename
        // fallback).
        eprintln!(
            "approval-tui: transcripts dir {} doesn't exist; agent-names won't update from transcript",
            dir.display()
        );
        return Ok(rx);
    }
    std::thread::Builder::new()
        .name("claude-transcripts-watcher".into())
        .spawn(move || run_watcher(dir, tx))
        .context("spawning transcript watcher thread")?;
    Ok(rx)
}

fn run_watcher(dir: PathBuf, tx: mpsc::UnboundedSender<TranscriptEvent>) {
    let tx_clone = tx.clone();
    let mut watcher = match recommended_watcher(move |res: notify::Result<notify::Event>| {
        match res {
            Ok(ev) => handle(ev, &tx_clone),
            Err(e) => {
                let _ = tx_clone.send(TranscriptEvent::Error(format!("watcher: {e}")));
            }
        }
    }) {
        Ok(w) => w,
        Err(e) => {
            let _ = tx.send(TranscriptEvent::Error(format!("creating watcher: {e}")));
            return;
        }
    };
    if let Err(e) = watcher.watch(&dir, RecursiveMode::Recursive) {
        let _ = tx.send(TranscriptEvent::Error(format!(
            "watching {}: {e}",
            dir.display()
        )));
        return;
    }
    loop {
        std::thread::park();
        if tx.is_closed() {
            return;
        }
    }
}

fn handle(ev: notify::Event, tx: &mpsc::UnboundedSender<TranscriptEvent>) {
    // We care about modifications and final creations of jsonl files;
    // small text appends typically surface as Modify(Data) or Modify(Any).
    let is_relevant = matches!(
        ev.kind,
        EventKind::Modify(_)
            | EventKind::Create(CreateKind::File)
            | EventKind::Create(CreateKind::Any)
    );
    if !is_relevant {
        return;
    }
    // Ignore pure rename-from / rename-to bookkeeping that doesn't imply
    // new data was appended.
    if matches!(ev.kind, EventKind::Modify(ModifyKind::Name(_))) {
        return;
    }
    for path in ev.paths {
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
        if !name.ends_with(".jsonl") {
            continue;
        }
        let claude_session_id = name.trim_end_matches(".jsonl").to_string();
        if claude_session_id.is_empty() {
            continue;
        }
        if let Some(latest) = latest_agent_name(&path) {
            let _ = tx.send(TranscriptEvent::AgentName {
                claude_session_id,
                name: latest,
            });
        }
    }
}

/// Re-read the whole jsonl file, find the last `agent-name` entry, return
/// its `agentName`. Returns None if there isn't one yet, the file can't
/// be read, or the JSON is malformed.
fn latest_agent_name(path: &Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    let s = std::str::from_utf8(&bytes).ok()?;
    let mut latest: Option<String> = None;
    for line in s.lines() {
        // Cheap pre-filter to skip obviously-irrelevant lines.
        if !line.contains("\"type\":\"agent-name\"") {
            continue;
        }
        let v: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if v.get("type").and_then(|t| t.as_str()) != Some("agent-name") {
            continue;
        }
        let Some(name) = v.get("agentName").and_then(|n| n.as_str()) else { continue };
        if name.is_empty() {
            continue;
        }
        latest = Some(name.to_string());
    }
    latest
}

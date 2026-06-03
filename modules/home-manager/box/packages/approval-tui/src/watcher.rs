use anyhow::{Context, Result};
use notify::event::{CreateKind, EventKind};
use notify::{recommended_watcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use tokio::sync::mpsc;

/// Events from the file watcher fanned out to the main loop.
#[derive(Debug)]
pub enum WatchEvent {
    /// A new request file has appeared (final, post-rename).
    NewRequest(PathBuf),
    /// Watcher hit an unrecoverable error.
    Error(String),
}

/// Events from the agent-events watcher (Claude Code Stop /
/// UserPromptSubmit hooks dropping JSON state markers).
#[derive(Debug)]
pub enum AgentEventNotice {
    NewEvent(PathBuf),
    Error(String),
}

/// Spawn a blocking thread that watches `request_dir` and forwards
/// CREATE-renamed-into-place events (which `mv` produces) to the caller.
pub fn spawn(request_dir: &Path) -> Result<mpsc::UnboundedReceiver<WatchEvent>> {
    let (tx, rx) = mpsc::unbounded_channel();
    let dir = request_dir.to_path_buf();
    std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;

    std::thread::Builder::new()
        .name("box-request-watcher".into())
        .spawn(move || run_watcher(dir, tx))
        .context("spawning watcher thread")?;

    Ok(rx)
}

fn run_watcher(dir: PathBuf, tx: mpsc::UnboundedSender<WatchEvent>) {
    let tx_clone = tx.clone();
    let mut watcher = match recommended_watcher(move |res: notify::Result<notify::Event>| {
        match res {
            Ok(ev) => handle_event(ev, &tx_clone),
            Err(e) => {
                let _ = tx_clone.send(WatchEvent::Error(format!("watcher: {e}")));
            }
        }
    }) {
        Ok(w) => w,
        Err(e) => {
            let _ = tx.send(WatchEvent::Error(format!("creating watcher: {e}")));
            return;
        }
    };
    if let Err(e) = watcher.watch(&dir, RecursiveMode::NonRecursive) {
        let _ = tx.send(WatchEvent::Error(format!("watching {}: {e}", dir.display())));
        return;
    }
    // Hold the watcher alive until the channel closes.
    loop {
        std::thread::park();
        if tx.is_closed() {
            return;
        }
    }
}

fn handle_event(ev: notify::Event, tx: &mpsc::UnboundedSender<WatchEvent>) {
    // We get CREATE for both staging files and final renames; pre-filter.
    let is_create_like = matches!(
        ev.kind,
        EventKind::Create(CreateKind::File)
            | EventKind::Create(CreateKind::Any)
            | EventKind::Modify(notify::event::ModifyKind::Name(_))
    );
    if !is_create_like {
        return;
    }
    for path in ev.paths {
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
        if name.starts_with('.') {
            // staging file — ignore
            continue;
        }
        if !name.ends_with(".json") {
            continue;
        }
        let _ = tx.send(WatchEvent::NewRequest(path));
    }
}

/// Same shape as `spawn`, but for the agent-events stream. Emits any
/// non-staging .json file as `AgentEventNotice::NewEvent`.
pub fn spawn_agent_events(
    events_dir: &Path,
) -> Result<mpsc::UnboundedReceiver<AgentEventNotice>> {
    let (tx, rx) = mpsc::unbounded_channel();
    let dir = events_dir.to_path_buf();
    std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    std::thread::Builder::new()
        .name("box-agent-events-watcher".into())
        .spawn(move || run_agent_events_watcher(dir, tx))
        .context("spawning agent-events watcher thread")?;
    Ok(rx)
}

fn run_agent_events_watcher(dir: PathBuf, tx: mpsc::UnboundedSender<AgentEventNotice>) {
    let tx_clone = tx.clone();
    let mut watcher = match recommended_watcher(move |res: notify::Result<notify::Event>| {
        match res {
            Ok(ev) => handle_agent_event(ev, &tx_clone),
            Err(e) => {
                let _ = tx_clone.send(AgentEventNotice::Error(format!("watcher: {e}")));
            }
        }
    }) {
        Ok(w) => w,
        Err(e) => {
            let _ = tx.send(AgentEventNotice::Error(format!("creating watcher: {e}")));
            return;
        }
    };
    if let Err(e) = watcher.watch(&dir, RecursiveMode::NonRecursive) {
        let _ = tx.send(AgentEventNotice::Error(format!(
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

fn handle_agent_event(ev: notify::Event, tx: &mpsc::UnboundedSender<AgentEventNotice>) {
    let is_create_like = matches!(
        ev.kind,
        EventKind::Create(CreateKind::File)
            | EventKind::Create(CreateKind::Any)
            | EventKind::Modify(notify::event::ModifyKind::Name(_))
    );
    if !is_create_like {
        return;
    }
    for path in ev.paths {
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
        if name.starts_with('.') || !name.ends_with(".json") {
            continue;
        }
        let _ = tx.send(AgentEventNotice::NewEvent(path));
    }
}

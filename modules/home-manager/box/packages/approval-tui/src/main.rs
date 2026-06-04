mod agents;
mod audit;
mod broker;
mod config;
mod queue;
mod response;
mod transcripts;
mod types;
mod ui;
mod watcher;

use crate::agents::{AgentEventFile, AgentRegistry};
use crate::audit::{sha256_hex, AuditEntry, AuditLog};
use crate::broker::gh_pr::{GhClient, GhPrCreate, GhPrEdit, GhPrReview, GhPrReviewAppend};
use crate::broker::git::{GitFetch, GitPull, GitPush, GitSignRange};
use crate::broker::Registry;
use crate::config::Config;
use crate::queue::Queue;
use crate::transcripts::TranscriptEvent;
use crate::response::{
    abandoned_response, dispatch_failed_response, ok_response, rejected_response, write_ack,
    write_response,
};
use crate::types::{RequestEnvelope, RequestState, ResponseStatus};
use crate::ui::UiState;
use crate::watcher::{AgentEventNotice, WatchEvent};
use anyhow::{Context, Result};
use chrono::Utc;
use crossterm::event::{Event, EventStream, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use futures::StreamExt;
use ratatui::Terminal;
use std::io;
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::time::Duration;

/// Outcome of an approval pipeline task (dispatch only — TUI approval no
/// longer signs; the downstream op (git push / git-sign-range / SSH)
/// triggers its own YubiKey touch when relevant). Sent back to the UI loop
/// so it can update state.
#[derive(Debug)]
enum PipelineOutcome {
    Ok {
        request_id: String,
        result: serde_json::Value,
    },
    DispatchFailed {
        request_id: String,
        detail: String,
    },
}

#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> Result<()> {
    let cfg = Config::from_env();
    let audit = AuditLog::new(cfg.audit_log.clone());
    let registry = Arc::new(build_registry(&cfg)?);

    let mut queue = Queue::new();
    let mut agents = AgentRegistry::new();
    let preloaded = queue
        .reload_from_dir(&cfg.request_dir())
        .context("reloading request dir on startup")?;
    if preloaded > 0 {
        eprintln!("approval-tui: reloaded {preloaded} pending request(s) from disk");
    }
    for env in queue.iter().map(|(_, r)| r.envelope.clone()).collect::<Vec<_>>() {
        agents.record_request(&env);
        // Acknowledge anything we already see on startup so the in-box
        // client knows we picked it up.
        write_ack(&cfg, &env.request_id).await.ok();
    }

    let mut watch_rx = watcher::spawn(&cfg.request_dir()).context("spawning request watcher")?;
    let mut agent_rx = watcher::spawn_agent_events(&cfg.agent_events_dir())
        .context("spawning agent-events watcher")?;
    let mut transcript_rx = transcripts::spawn(&cfg.claude_projects_dir)
        .context("spawning transcript watcher")?;
    let (pipeline_tx, mut pipeline_rx) = mpsc::unbounded_channel::<PipelineOutcome>();

    let mut terminal = init_terminal().context("entering raw mode + alt screen")?;
    let result = run_event_loop(
        &mut terminal,
        &cfg,
        audit,
        registry,
        &mut queue,
        &mut agents,
        &mut watch_rx,
        &mut agent_rx,
        &mut transcript_rx,
        &mut pipeline_rx,
        pipeline_tx,
    )
    .await;

    restore_terminal()?;
    result
}

#[allow(clippy::too_many_arguments)]
async fn run_event_loop<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    cfg: &Config,
    audit: AuditLog,
    registry: Arc<Registry>,
    queue: &mut Queue,
    agents: &mut AgentRegistry,
    watch_rx: &mut mpsc::UnboundedReceiver<WatchEvent>,
    agent_rx: &mut mpsc::UnboundedReceiver<AgentEventNotice>,
    transcript_rx: &mut mpsc::UnboundedReceiver<TranscriptEvent>,
    pipeline_rx: &mut mpsc::UnboundedReceiver<PipelineOutcome>,
    pipeline_tx: mpsc::UnboundedSender<PipelineOutcome>,
) -> Result<()> {
    let mut ui_state = UiState::default();
    let mut events = EventStream::new();
    let mut tick = tokio::time::interval(Duration::from_millis(500));

    loop {
        terminal.draw(|f| ui::draw(f, queue, agents, &ui_state))?;

        tokio::select! {
            biased;

            ev = events.next() => {
                let Some(Ok(ev)) = ev else { continue };
                let action = handle_input(&ev);
                if matches!(action, InputAction::Quit) {
                    break;
                }
                apply_action(action, cfg, &audit, &registry, queue, agents, &mut ui_state, &pipeline_tx).await?;
            }

            Some(watch_ev) = watch_rx.recv() => {
                match watch_ev {
                    WatchEvent::NewRequest(path) => {
                        match queue.try_enqueue(path) {
                            Ok(Some(req)) => {
                                let id = req.envelope.request_id.clone();
                                let op = req.envelope.op.clone();
                                let summary = req.envelope.summary.clone();
                                agents.record_request(&req.envelope);
                                write_ack(cfg, &id).await.ok();
                                ui_state.message = Some(format!("queued {id}"));
                                let body = match summary {
                                    Some(s) if !s.is_empty() => format!("{op}: {s}"),
                                    _ => op,
                                };
                                tokio::spawn(async move {
                                    dispatch_notification("Approval requested", &body).await;
                                });
                            }
                            Ok(None) => {} // already seen
                            Err(e) => {
                                ui_state.message = Some(format!("watch enqueue error: {e:#}"));
                            }
                        }
                    }
                    WatchEvent::Error(msg) => {
                        ui_state.message = Some(format!("watcher: {msg}"));
                    }
                }
            }

            Some(outcome) = pipeline_rx.recv() => {
                handle_outcome(outcome, cfg, &audit, queue, agents, &mut ui_state).await?;
            }

            Some(agent_ev) = agent_rx.recv() => {
                match agent_ev {
                    AgentEventNotice::NewEvent(path) => {
                        match tokio::fs::read(&path).await {
                            Ok(bytes) => match serde_json::from_slice::<AgentEventFile>(&bytes) {
                                Ok(event) => {
                                    // Update the bottom pane only — no
                                    // desktop notification on ready
                                    // (intentionally; the pane is enough
                                    // and notify-send was too noisy).
                                    let _ = agents.apply_event(event);
                                }
                                Err(e) => ui_state.message = Some(format!("agent-event parse: {e:#}")),
                            },
                            // ENOENT is a benign race: inotify can fire
                            // twice for the same file (Create + Modify),
                            // and we delete it after the first successful
                            // read. Silence those; surface anything else.
                            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                            Err(e) => ui_state.message = Some(format!("agent-event read: {e:#}")),
                        }
                        let _ = tokio::fs::remove_file(&path).await;
                    }
                    AgentEventNotice::Error(msg) => {
                        ui_state.message = Some(format!("agent-events watcher: {msg}"));
                    }
                }
            }

            Some(transcript_ev) = transcript_rx.recv() => {
                match transcript_ev {
                    TranscriptEvent::AgentName { claude_session_id, name } => {
                        agents.update_name_by_claude_session(&claude_session_id, name);
                    }
                    TranscriptEvent::Error(msg) => {
                        ui_state.message = Some(format!("transcript watcher: {msg}"));
                    }
                }
            }

            _ = tick.tick() => {} // periodic redraw
        }
    }
    Ok(())
}

enum InputAction {
    None,
    Quit,
    Next,
    Prev,
    ToggleHelp,
    Approve,
    Reject,
    Retry,
}

fn handle_input(event: &Event) -> InputAction {
    let Event::Key(key) = event else { return InputAction::None };
    if key.kind != KeyEventKind::Press {
        return InputAction::None;
    }
    if key.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        return InputAction::Quit;
    }
    match key.code {
        KeyCode::Char('q') => InputAction::Quit,
        KeyCode::Char('j') | KeyCode::Down => InputAction::Next,
        KeyCode::Char('k') | KeyCode::Up => InputAction::Prev,
        KeyCode::Char('?') => InputAction::ToggleHelp,
        KeyCode::Enter => InputAction::Approve,
        KeyCode::Char('d') => InputAction::Reject,
        KeyCode::Char('r') => InputAction::Retry,
        _ => InputAction::None,
    }
}

#[allow(clippy::too_many_arguments)]
async fn apply_action(
    action: InputAction,
    cfg: &Config,
    audit: &AuditLog,
    registry: &Arc<Registry>,
    queue: &mut Queue,
    agents: &mut AgentRegistry,
    state: &mut UiState,
    pipeline_tx: &mpsc::UnboundedSender<PipelineOutcome>,
) -> Result<()> {
    match action {
        InputAction::None | InputAction::Quit => {}
        InputAction::Next => queue.select_next(),
        InputAction::Prev => queue.select_prev(),
        InputAction::ToggleHelp => state.help_visible = !state.help_visible,
        InputAction::Approve | InputAction::Retry => {
            if let Some(id) = queue.selected_id() {
                approve_request(&id, cfg, audit, registry, queue, state, pipeline_tx).await?;
            }
        }
        InputAction::Reject => {
            if let Some(id) = queue.selected_id() {
                reject_request(&id, cfg, audit, queue, agents, state).await?;
            }
        }
    }
    Ok(())
}

async fn approve_request(
    id: &str,
    cfg: &Config,
    audit: &AuditLog,
    registry: &Arc<Registry>,
    queue: &mut Queue,
    state: &mut UiState,
    pipeline_tx: &mpsc::UnboundedSender<PipelineOutcome>,
) -> Result<()> {
    let Some(req) = queue.get_mut(id) else { return Ok(()) };
    if matches!(req.state, RequestState::Dispatching) {
        state.message = Some(format!("{id} already in-flight"));
        return Ok(());
    }
    req.state = RequestState::Dispatching;
    req.last_error = None;
    let envelope = req.envelope.clone();
    state.message = Some(format!("dispatching {id}"));

    let tx = pipeline_tx.clone();
    let registry = registry.clone();
    let audit = audit.clone();
    let _ = cfg; // kept in signature for symmetry; unused now that there's no signing step
    let id_owned = id.to_string();

    tokio::spawn(async move {
        run_pipeline(envelope, audit, registry, id_owned, tx).await;
    });
    Ok(())
}

/// Stable SHA-256 hash of the request payload, recorded in the audit log so
/// each approval is anchored to the exact payload bytes the user saw.
fn payload_sha256(envelope: &RequestEnvelope) -> String {
    let bytes = serde_json::to_vec(&envelope.payload).unwrap_or_default();
    sha256_hex(&bytes)
}

async fn run_pipeline(
    envelope: RequestEnvelope,
    audit: AuditLog,
    registry: Arc<Registry>,
    id: String,
    tx: mpsc::UnboundedSender<PipelineOutcome>,
) {
    let payload_sha = payload_sha256(&envelope);

    match registry.dispatch(&envelope).await {
        Ok(result) => {
            let _ = audit
                .append(&AuditEntry {
                    recorded_at: Utc::now().to_rfc3339(),
                    request_id: &id,
                    op: &envelope.op,
                    status: ResponseStatus::Ok,
                    signature: None,
                    canonical_sha256: Some(&payload_sha),
                    result: Some(&result),
                    error: None,
                })
                .await;
            let _ = tx.send(PipelineOutcome::Ok {
                request_id: id,
                result,
            });
        }
        Err(e) => {
            let detail = format!("{e:#}");
            let _ = audit
                .append(&AuditEntry {
                    recorded_at: Utc::now().to_rfc3339(),
                    request_id: &id,
                    op: &envelope.op,
                    status: ResponseStatus::DispatchFailed,
                    signature: None,
                    canonical_sha256: Some(&payload_sha),
                    result: None,
                    error: Some(&detail),
                })
                .await;
            let _ = tx.send(PipelineOutcome::DispatchFailed {
                request_id: id,
                detail,
            });
        }
    }
}

async fn reject_request(
    id: &str,
    cfg: &Config,
    audit: &AuditLog,
    queue: &mut Queue,
    agents: &mut AgentRegistry,
    state: &mut UiState,
) -> Result<()> {
    let (op, envelope_for_agents) = queue
        .get_mut(id)
        .map(|r| (r.envelope.op.clone(), Some(r.envelope.clone())))
        .unwrap_or_default();
    write_response(cfg, id, &rejected_response()).await?;
    audit
        .append(&AuditEntry {
            recorded_at: Utc::now().to_rfc3339(),
            request_id: id,
            op: &op,
            status: ResponseStatus::Rejected,
            signature: None,
            canonical_sha256: None,
            result: None,
            error: None,
        })
        .await?;
    let removed = queue.remove(id);
    if let Some(env) = envelope_for_agents {
        agents.complete_request(&env);
    }
    cleanup_request_file(removed).await;
    state.message = Some(format!("rejected {id}"));
    Ok(())
}

async fn handle_outcome(
    outcome: PipelineOutcome,
    cfg: &Config,
    _audit: &AuditLog,
    queue: &mut Queue,
    agents: &mut AgentRegistry,
    state: &mut UiState,
) -> Result<()> {
    match outcome {
        PipelineOutcome::Ok { request_id, result } => {
            let env_clone = queue.get_mut(&request_id).map(|r| r.envelope.clone());
            write_response(cfg, &request_id, &ok_response(result)).await?;
            let removed = queue.remove(&request_id);
            if let Some(env) = env_clone {
                agents.complete_request(&env);
            }
            cleanup_request_file(removed).await;
            state.message = Some(format!("ok {request_id}"));
        }
        PipelineOutcome::DispatchFailed {
            request_id,
            detail,
        } => {
            // Dispatch failed — write response so the box client unblocks.
            // The user can also re-trigger via retry if appropriate.
            let env_clone = queue.get_mut(&request_id).map(|r| r.envelope.clone());
            write_response(cfg, &request_id, &dispatch_failed_response(detail.clone())).await?;
            let removed = queue.remove(&request_id);
            if let Some(env) = env_clone {
                agents.complete_request(&env);
            }
            cleanup_request_file(removed).await;
            state.message = Some(format!("dispatch failed: {detail}"));
        }
    }
    Ok(())
}

/// Fire a desktop notification via notify-send and (best-effort) play the
/// message sound. Both invocations are detached: we don't block the event
/// loop on either.
///
/// `BOX_NOTIFY_BIN` / `BOX_PW_CAT_BIN` / `BOX_NOTIFY_SOUND` env vars
/// provide absolute paths (set by the home-manager module). Falls back
/// to PATH lookup if a binary path env var is unset; logs to stderr if
/// the notify-send invocation can't even be spawned, so the user sees
/// it in the TUI's launching terminal.
async fn dispatch_notification(title: &str, body: &str) {
    let pw_cat = std::env::var("BOX_PW_CAT_BIN").unwrap_or_else(|_| "pw-cat".into());
    if let Ok(sound) = std::env::var("BOX_NOTIFY_SOUND") {
        if !sound.is_empty() {
            tokio::spawn(async move {
                let _ = tokio::process::Command::new(&pw_cat)
                    .args(["--playback", &sound])
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .status()
                    .await;
            });
        }
    }
    let notify_bin = std::env::var("BOX_NOTIFY_BIN").unwrap_or_else(|_| "notify-send".into());
    let result = tokio::process::Command::new(&notify_bin)
        .args(["--app-name=approval-tui", "--", title, body])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .await;
    if let Err(e) = result {
        eprintln!("approval-tui: notify-send failed to spawn ({notify_bin}): {e:#}");
    }
}

async fn cleanup_request_file(req: Option<crate::types::PendingRequest>) {
    if let Some(r) = req {
        // Best-effort: remove the request file so the dir doesn't grow.
        let _ = tokio::fs::remove_file(&r.source_path).await;
    }
}

fn init_terminal() -> Result<Terminal<ratatui::backend::CrosstermBackend<io::Stdout>>> {
    enable_raw_mode().context("enable_raw_mode")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("EnterAlternateScreen")?;
    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    Terminal::new(backend).context("creating terminal")
}

fn restore_terminal() -> Result<()> {
    disable_raw_mode().ok();
    execute!(io::stdout(), LeaveAlternateScreen).ok();
    Ok(())
}

// keep the abandoned helper exported (used when implementing restart-resume)
#[allow(dead_code)]
async fn write_abandoned(cfg: &Config, request_id: &str, reason: &str) -> Result<()> {
    write_response(cfg, request_id, &abandoned_response(reason.into())).await
}

fn build_registry(cfg: &Config) -> Result<Registry> {
    let mut reg = Registry::new();
    if let Some(pat) = cfg.gh_pat_file.clone() {
        let client = GhClient::new(pat).context("building GitHub client")?;
        reg.register(Box::new(GhPrCreate {
            client: client.clone(),
        }));
        reg.register(Box::new(GhPrEdit {
            client: client.clone(),
        }));
        reg.register(Box::new(GhPrReview { client: client.clone() }));
        reg.register(Box::new(GhPrReviewAppend { client }));
    } else {
        eprintln!(
            "approval-tui: BOX_GH_PAT_FILE not set — gh.pr.* brokers will fail with \
             'no broker registered'. Set the env var in the systemd service to enable them."
        );
    }
    reg.register(Box::new(GitPush));
    reg.register(Box::new(GitPull));
    reg.register(Box::new(GitFetch));
    reg.register(Box::new(GitSignRange));
    Ok(reg)
}

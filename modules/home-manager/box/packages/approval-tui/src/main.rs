mod audit;
mod broker;
mod config;
mod queue;
mod response;
mod signing;
mod types;
mod ui;
mod watcher;

use crate::audit::{sha256_hex, AuditEntry, AuditLog};
use crate::broker::gh_pr::{GhClient, GhPrCreate, GhPrEdit, GhPrReview};
use crate::broker::git::{GitFetch, GitPull, GitPush, GitSignRange};
use crate::broker::Registry;
use crate::config::Config;
use crate::queue::Queue;
use crate::response::{
    abandoned_response, dispatch_failed_response, ok_response, rejected_response,
    sign_failed_response, write_ack, write_response,
};
use crate::types::{RequestEnvelope, RequestState, ResponseStatus};
use crate::ui::UiState;
use crate::watcher::WatchEvent;
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

/// Outcome of an approval pipeline task (signing + dispatch). Sent back to
/// the UI loop so it can update state.
#[derive(Debug)]
enum PipelineOutcome {
    Ok {
        request_id: String,
        result: serde_json::Value,
    },
    SignFailed {
        request_id: String,
        detail: String,
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
    let preloaded = queue
        .reload_from_dir(&cfg.request_dir())
        .context("reloading request dir on startup")?;
    if preloaded > 0 {
        eprintln!("approval-tui: reloaded {preloaded} pending request(s) from disk");
    }
    for req in queue.iter().map(|(_, r)| r.envelope.request_id.clone()).collect::<Vec<_>>() {
        // Acknowledge anything we already see on startup so the in-box
        // client knows we picked it up.
        write_ack(&cfg, &req).await.ok();
    }

    let mut watch_rx = watcher::spawn(&cfg.request_dir()).context("spawning request watcher")?;
    let (pipeline_tx, mut pipeline_rx) = mpsc::unbounded_channel::<PipelineOutcome>();

    let mut terminal = init_terminal().context("entering raw mode + alt screen")?;
    let result = run_event_loop(
        &mut terminal,
        &cfg,
        audit,
        registry,
        &mut queue,
        &mut watch_rx,
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
    watch_rx: &mut mpsc::UnboundedReceiver<WatchEvent>,
    pipeline_rx: &mut mpsc::UnboundedReceiver<PipelineOutcome>,
    pipeline_tx: mpsc::UnboundedSender<PipelineOutcome>,
) -> Result<()> {
    let mut ui_state = UiState::default();
    let mut events = EventStream::new();
    let mut tick = tokio::time::interval(Duration::from_millis(500));

    loop {
        terminal.draw(|f| ui::draw(f, queue, &ui_state))?;

        tokio::select! {
            biased;

            ev = events.next() => {
                let Some(Ok(ev)) = ev else { continue };
                let action = handle_input(&ev);
                if matches!(action, InputAction::Quit) {
                    break;
                }
                apply_action(action, cfg, &audit, &registry, queue, &mut ui_state, &pipeline_tx).await?;
            }

            Some(watch_ev) = watch_rx.recv() => {
                match watch_ev {
                    WatchEvent::NewRequest(path) => {
                        match queue.try_enqueue(path) {
                            Ok(Some(req)) => {
                                let id = req.envelope.request_id.clone();
                                write_ack(cfg, &id).await.ok();
                                ui_state.message = Some(format!("queued {id}"));
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
                handle_outcome(outcome, cfg, &audit, queue, &mut ui_state).await?;
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

async fn apply_action(
    action: InputAction,
    cfg: &Config,
    audit: &AuditLog,
    registry: &Arc<Registry>,
    queue: &mut Queue,
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
                reject_request(&id, cfg, audit, queue, state).await?;
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
    if matches!(req.state, RequestState::Signing | RequestState::Dispatching) {
        state.message = Some(format!("{id} already in-flight"));
        return Ok(());
    }
    req.state = RequestState::Signing;
    req.last_error = None;
    let envelope = req.envelope.clone();
    state.message = Some(format!("signing {id} — touch YubiKey"));

    let tx = pipeline_tx.clone();
    let registry = registry.clone();
    let audit = audit.clone();
    let cfg = cfg.clone();
    let id_owned = id.to_string();

    tokio::spawn(async move {
        run_pipeline(envelope, cfg, audit, registry, id_owned, tx).await;
    });
    Ok(())
}

async fn run_pipeline(
    envelope: RequestEnvelope,
    cfg: Config,
    audit: AuditLog,
    registry: Arc<Registry>,
    id: String,
    tx: mpsc::UnboundedSender<PipelineOutcome>,
) {
    let signed = match signing::sign_envelope(&envelope, &cfg.signing_key).await {
        Ok(s) => s,
        Err(e) => {
            let detail = format!("{e:#}");
            let _ = audit
                .append(&AuditEntry {
                    recorded_at: Utc::now().to_rfc3339(),
                    request_id: &id,
                    op: &envelope.op,
                    status: ResponseStatus::SignFailed,
                    signature: None,
                    canonical_sha256: None,
                    result: None,
                    error: Some(&detail),
                })
                .await;
            let _ = tx.send(PipelineOutcome::SignFailed {
                request_id: id,
                detail,
            });
            return;
        }
    };
    let canonical_sha = sha256_hex(&signed.canonical_bytes);

    match registry.dispatch(&envelope).await {
        Ok(result) => {
            let _ = audit
                .append(&AuditEntry {
                    recorded_at: Utc::now().to_rfc3339(),
                    request_id: &id,
                    op: &envelope.op,
                    status: ResponseStatus::Ok,
                    signature: Some(&signed.signature),
                    canonical_sha256: Some(&canonical_sha),
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
                    signature: Some(&signed.signature),
                    canonical_sha256: Some(&canonical_sha),
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
    state: &mut UiState,
) -> Result<()> {
    let op = queue.get_mut(id).map(|r| r.envelope.op.clone()).unwrap_or_default();
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
    cleanup_request_file(removed).await;
    state.message = Some(format!("rejected {id}"));
    Ok(())
}

async fn handle_outcome(
    outcome: PipelineOutcome,
    cfg: &Config,
    _audit: &AuditLog,
    queue: &mut Queue,
    state: &mut UiState,
) -> Result<()> {
    match outcome {
        PipelineOutcome::Ok { request_id, result } => {
            write_response(cfg, &request_id, &ok_response(result)).await?;
            let removed = queue.remove(&request_id);
            cleanup_request_file(removed).await;
            state.message = Some(format!("ok {request_id}"));
        }
        PipelineOutcome::SignFailed { request_id, detail } => {
            if let Some(req) = queue.get_mut(&request_id) {
                req.state = RequestState::SignFailed;
                req.last_error = Some(detail.clone());
            }
            // Don't write the response yet — let the user retry. We only
            // emit the response file when the user gives up (closes via
            // reject, or when we exit / abandon).
            state.message = Some(format!("sign failed: {detail}"));
        }
        PipelineOutcome::DispatchFailed {
            request_id,
            detail,
        } => {
            // Dispatch failed but signature is recorded; write response so
            // the box client unblocks. User can also re-trigger via retry
            // if appropriate.
            write_response(cfg, &request_id, &dispatch_failed_response(detail.clone())).await?;
            let removed = queue.remove(&request_id);
            cleanup_request_file(removed).await;
            state.message = Some(format!("dispatch failed: {detail}"));
        }
    }
    Ok(())
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
        reg.register(Box::new(GhPrReview { client }));
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

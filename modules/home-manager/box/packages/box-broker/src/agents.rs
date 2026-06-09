use crate::types::RequestEnvelope;
use serde::Deserialize;
use std::collections::HashMap;
use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentState {
    /// Agent is actively processing a user prompt (UserPromptSubmit hook
    /// fired and we haven't seen Stop yet).
    Working,
    /// Agent finished its turn and is awaiting the next user prompt
    /// (Stop hook fired).
    Ready,
    /// We've only seen broker requests from this agent, not the Claude
    /// Code state hooks — can't tell whether it's working or ready.
    Unknown,
}

impl AgentState {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Working => "working",
            Self::Ready => "ready",
            Self::Unknown => "active",
        }
    }
}

#[derive(Debug, Clone)]
pub struct AgentEntry {
    pub session_id: String,
    /// Display name for this agent, sourced from Claude Code's transcript
    /// (`agent-name` lines in `~/.claude/projects/<slug>/<uuid>.jsonl`).
    /// None until the transcript watcher finds one — UI falls back to cwd.
    pub name: Option<String>,
    /// Claude Code's session UUID, recorded the first time `agent-hook`
    /// fires for this box session. Lets the transcript watcher cross-
    /// reference jsonl files (`<uuid>.jsonl`) back to this AgentEntry.
    pub claude_session_id: Option<String>,
    /// Last-known cwd from a request envelope (basename for display).
    pub cwd: String,
    /// Number of requests this agent currently has in the queue (pending +
    /// dispatching). Independent of `state` (an agent can be Working while
    /// no requests are in-flight, or Ready while a request is in-flight).
    pub in_flight: u32,
    pub total_seen: u32,
    pub state: AgentState,
    pub last_seen: Instant,
}

impl AgentEntry {
    /// Display label: explicit `name` if set, else cwd basename.
    pub fn label(&self) -> &str {
        self.name.as_deref().unwrap_or(&self.cwd)
    }
}

/// JSON shape of `${brokerRoot}/agent-events/<id>.json`, produced by the
/// in-box `agent-event` script via Claude Code's UserPromptSubmit / Stop
/// hooks.
#[derive(Debug, Deserialize)]
pub struct AgentEventFile {
    pub event: String,
    pub session_id: String,
    pub cwd: String,
    #[serde(default)]
    pub claude_session_id: Option<String>,
    #[allow(dead_code)]
    pub ts: String,
}

/// What happened to an agent's state as a result of applying an event.
/// Lets the caller decide whether to fire a desktop notification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentTransition {
    /// Nothing changed.
    NoChange,
    /// Agent newly tracked.
    Created(AgentState),
    /// Agent's state changed.
    Changed { from: AgentState, to: AgentState },
}

#[derive(Debug, Default)]
pub struct AgentRegistry {
    by_session: HashMap<String, AgentEntry>,
}

impl AgentRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record a broker request from an agent. Bumps the in-flight + total
    /// counters; doesn't change `state` (state comes from agent-events).
    pub fn record_request(&mut self, envelope: &RequestEnvelope) {
        let Some(ctx) = envelope.client_context.as_ref() else {
            return;
        };
        let session_id = ctx
            .session_id
            .clone()
            .unwrap_or_else(|| format!("pid-{}", ctx.agent_pid));
        let cwd = display_cwd(&ctx.cwd);
        let entry = self
            .by_session
            .entry(session_id.clone())
            .or_insert_with(|| AgentEntry {
                session_id: session_id.clone(),
                name: None,
                claude_session_id: None,
                cwd: cwd.clone(),
                in_flight: 0,
                total_seen: 0,
                state: AgentState::Unknown,
                last_seen: Instant::now(),
            });
        entry.cwd = cwd;
        entry.in_flight = entry.in_flight.saturating_add(1);
        entry.total_seen = entry.total_seen.saturating_add(1);
        entry.last_seen = Instant::now();
    }

    /// Decrement the in-flight counter when a request resolves.
    pub fn complete_request(&mut self, envelope: &RequestEnvelope) {
        let Some(ctx) = envelope.client_context.as_ref() else {
            return;
        };
        let session_id = ctx
            .session_id
            .clone()
            .unwrap_or_else(|| format!("pid-{}", ctx.agent_pid));
        if let Some(entry) = self.by_session.get_mut(&session_id) {
            entry.in_flight = entry.in_flight.saturating_sub(1);
            entry.last_seen = Instant::now();
        }
    }

    /// Apply a Claude Code state-hook event. Returns the transition so the
    /// caller can decide whether to fire a desktop notification (we
    /// typically only notify on Working/Unknown → Ready, since that's the
    /// "your agent is waiting on you" moment).
    pub fn apply_event(&mut self, event: AgentEventFile) -> AgentTransition {
        // Terminated → drop the entry. The box session is gone; nothing
        // more to display for it.
        if event.event == "terminated" {
            self.by_session.remove(&event.session_id);
            return AgentTransition::NoChange;
        }
        let new_state = match event.event.as_str() {
            "working" => AgentState::Working,
            "ready" => AgentState::Ready,
            _ => return AgentTransition::NoChange,
        };
        let cwd = display_cwd(&event.cwd);
        let session_id = event.session_id;
        let claude_session_id = event.claude_session_id.filter(|s| !s.is_empty());
        match self.by_session.get_mut(&session_id) {
            Some(entry) => {
                let from = entry.state;
                entry.cwd = cwd;
                entry.state = new_state;
                if let Some(uuid) = claude_session_id {
                    entry.claude_session_id = Some(uuid);
                }
                entry.last_seen = Instant::now();
                if from == new_state {
                    AgentTransition::NoChange
                } else {
                    AgentTransition::Changed { from, to: new_state }
                }
            }
            None => {
                self.by_session.insert(
                    session_id.clone(),
                    AgentEntry {
                        session_id,
                        name: None,
                        claude_session_id,
                        cwd,
                        in_flight: 0,
                        total_seen: 0,
                        state: new_state,
                        last_seen: Instant::now(),
                    },
                );
                AgentTransition::Created(new_state)
            }
        }
    }

    /// Update the display name for the agent whose `claude_session_id`
    /// matches `uuid`. Called by the transcript watcher when it sees a
    /// new `agent-name` line. No-op if no agent has that UUID yet.
    pub fn update_name_by_claude_session(&mut self, uuid: &str, name: String) -> bool {
        if name.is_empty() {
            return false;
        }
        let mut changed = false;
        for entry in self.by_session.values_mut() {
            if entry.claude_session_id.as_deref() == Some(uuid) {
                if entry.name.as_deref() != Some(name.as_str()) {
                    entry.name = Some(name.clone());
                    entry.last_seen = Instant::now();
                    changed = true;
                }
            }
        }
        changed
    }

    /// Iterate agents in last-seen-first order, capped at `max` rows.
    pub fn recent(&self, max: usize) -> Vec<&AgentEntry> {
        let mut v: Vec<&AgentEntry> = self.by_session.values().collect();
        v.sort_by(|a, b| b.last_seen.cmp(&a.last_seen));
        v.truncate(max);
        v
    }

    pub fn len(&self) -> usize {
        self.by_session.len()
    }
}

fn display_cwd(raw: &str) -> String {
    std::path::Path::new(raw)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(raw)
        .to_string()
}

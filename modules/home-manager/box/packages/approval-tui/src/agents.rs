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

/// JSON shape of `${brokerRoot}/agent-events/<id>.json`, produced by the
/// in-box `agent-event` script via Claude Code's UserPromptSubmit / Stop
/// hooks.
#[derive(Debug, Deserialize)]
pub struct AgentEventFile {
    pub event: String,
    pub session_id: String,
    pub cwd: String,
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
        let new_state = match event.event.as_str() {
            "working" => AgentState::Working,
            "ready" => AgentState::Ready,
            _ => return AgentTransition::NoChange,
        };
        let cwd = display_cwd(&event.cwd);
        let session_id = event.session_id;
        match self.by_session.get_mut(&session_id) {
            Some(entry) => {
                let from = entry.state;
                entry.cwd = cwd;
                entry.state = new_state;
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

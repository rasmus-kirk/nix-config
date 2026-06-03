use crate::types::RequestEnvelope;
use std::collections::HashMap;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct AgentEntry {
    pub session_id: String,
    /// Last-known cwd from a request envelope (basename for display).
    pub cwd: String,
    /// Number of requests this agent currently has in the queue (pending +
    /// dispatching). Zero ⇒ "ready"; non-zero ⇒ "working".
    pub in_flight: u32,
    /// Total requests this agent has ever submitted while we've been
    /// running. Useful as a "noisy" indicator.
    pub total_seen: u32,
    pub last_seen: Instant,
}

impl AgentEntry {
    pub fn status_label(&self) -> &'static str {
        if self.in_flight > 0 {
            "working"
        } else {
            "ready"
        }
    }
}

#[derive(Debug, Default)]
pub struct AgentRegistry {
    by_session: HashMap<String, AgentEntry>,
}

impl AgentRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record a new request from an agent. Idempotent for the same envelope
    /// being seen twice (the queue dedupes; this just keeps the counts in
    /// sync with the queue's view).
    pub fn record_request(&mut self, envelope: &RequestEnvelope) {
        let Some(ctx) = envelope.client_context.as_ref() else {
            return;
        };
        let session_id = ctx
            .session_id
            .clone()
            .unwrap_or_else(|| format!("pid-{}", ctx.agent_pid));
        let cwd = std::path::Path::new(&ctx.cwd)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(&ctx.cwd)
            .to_string();
        let entry = self
            .by_session
            .entry(session_id.clone())
            .or_insert_with(|| AgentEntry {
                session_id: session_id.clone(),
                cwd: cwd.clone(),
                in_flight: 0,
                total_seen: 0,
                last_seen: Instant::now(),
            });
        entry.cwd = cwd;
        entry.in_flight = entry.in_flight.saturating_add(1);
        entry.total_seen = entry.total_seen.saturating_add(1);
        entry.last_seen = Instant::now();
    }

    /// Decrement the in-flight counter for the agent owning `envelope`.
    /// Called when a request resolves (ok / dispatch_failed / rejected).
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

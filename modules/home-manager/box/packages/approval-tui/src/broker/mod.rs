use crate::types::RequestEnvelope;
use anyhow::{anyhow, Result};
use serde_json::Value;
use std::future::Future;
use std::pin::Pin;

pub mod gh_pr;

pub type BrokerFuture<'a> = Pin<Box<dyn Future<Output = Result<Value>> + Send + 'a>>;

/// A broker dispatches an approved request against the underlying service
/// (GitHub API, git CLI, Linear, …). Each op has its own impl. Brokers are
/// invoked AFTER the user has approved (Enter + YubiKey touch) — so an impl
/// can assume consent.
///
/// `dispatch` returns a boxed future rather than `async fn` so the trait is
/// dyn-compatible (we hold brokers as `Box<dyn Broker>` in the registry).
pub trait Broker: Send + Sync {
    /// Dotted operation identifier, e.g. `"gh.pr.create"`.
    fn op_id(&self) -> &'static str;

    /// One-line human summary for the TUI detail pane. Always available
    /// without network — Haiku-augmented summaries are optional on top.
    fn fallback_summary(&self, envelope: &RequestEnvelope) -> String;

    /// Run the action. Return the broker-specific JSON result on success.
    fn dispatch<'a>(&'a self, envelope: &'a RequestEnvelope) -> BrokerFuture<'a>;
}

/// Registry: op_id → Broker. Populated at construction time.
pub struct Registry {
    brokers: Vec<Box<dyn Broker>>,
}

impl Registry {
    pub fn new() -> Self {
        Self {
            brokers: Vec::new(),
        }
    }

    pub fn register(&mut self, broker: Box<dyn Broker>) {
        self.brokers.push(broker);
    }

    pub fn get(&self, op_id: &str) -> Option<&dyn Broker> {
        self.brokers
            .iter()
            .find(|b| b.op_id() == op_id)
            .map(|b| b.as_ref())
    }

    pub fn fallback_summary(&self, envelope: &RequestEnvelope) -> String {
        if let Some(b) = self.get(&envelope.op) {
            b.fallback_summary(envelope)
        } else {
            format!("unknown op `{}`", envelope.op)
        }
    }

    pub fn dispatch<'a>(&'a self, envelope: &'a RequestEnvelope) -> BrokerFuture<'a> {
        Box::pin(async move {
            let broker = self
                .get(&envelope.op)
                .ok_or_else(|| anyhow!("no broker registered for op `{}`", envelope.op))?;
            broker.dispatch(envelope).await
        })
    }
}

impl Default for Registry {
    fn default() -> Self {
        Self::new()
    }
}

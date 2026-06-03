use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Instant;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestEnvelope {
    pub v: u8,
    pub request_id: String,
    pub requested_at: String,
    pub op: String,
    pub payload: serde_json::Value,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub client_context: Option<ClientContext>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientContext {
    pub cwd: String,
    pub agent_pid: u32,
    pub started_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedEnvelope {
    pub envelope: RequestEnvelope,
    pub approved_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub status: ResponseStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ResponseStatus {
    Ok,
    Rejected,
    SignFailed,
    DispatchFailed,
    Abandoned,
}

#[derive(Debug)]
pub struct PendingRequest {
    pub envelope: RequestEnvelope,
    pub source_path: PathBuf,
    pub received_at: Instant,
    pub state: RequestState,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequestState {
    Pending,
    Signing,
    Dispatching,
    SignFailed,
    DispatchFailed,
}

impl RequestState {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Signing => "signing",
            Self::Dispatching => "dispatching",
            Self::SignFailed => "sign failed",
            Self::DispatchFailed => "dispatch failed",
        }
    }
}

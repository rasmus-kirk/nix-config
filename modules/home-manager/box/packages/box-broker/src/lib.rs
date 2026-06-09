//! Shared surface between the host approval-tui binary and the in-box
//! box-broker binary. Keep this small: types that travel over the
//! file-drop IPC + the helper that submits a request and waits for a
//! response. Everything host-specific (queue, watcher, ui, brokers)
//! stays out of the lib so the box-broker binary doesn't pull it.

pub mod broker_client;
pub mod types;

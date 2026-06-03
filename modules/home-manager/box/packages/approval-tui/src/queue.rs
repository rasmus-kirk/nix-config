use crate::types::{PendingRequest, RequestEnvelope, RequestState};
use anyhow::{Context, Result};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Debug, Default)]
pub struct Queue {
    order: Vec<String>,
    items: HashMap<String, PendingRequest>,
    seen_ids: HashMap<String, ()>,
    selected: usize,
}

impl Queue {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn try_enqueue(&mut self, path: PathBuf) -> Result<Option<&PendingRequest>> {
        let bytes = std::fs::read(&path)
            .with_context(|| format!("reading request file {}", path.display()))?;
        let envelope: RequestEnvelope = serde_json::from_slice(&bytes)
            .with_context(|| format!("parsing request envelope at {}", path.display()))?;
        let id = envelope.request_id.clone();
        if self.seen_ids.contains_key(&id) {
            return Ok(None);
        }
        self.seen_ids.insert(id.clone(), ());
        let req = PendingRequest {
            envelope,
            source_path: path,
            received_at: Instant::now(),
            state: RequestState::Pending,
            last_error: None,
        };
        self.order.push(id.clone());
        self.items.insert(id.clone(), req);
        Ok(self.items.get(&id))
    }

    pub fn remove(&mut self, id: &str) -> Option<PendingRequest> {
        if let Some(idx) = self.order.iter().position(|x| x == id) {
            self.order.remove(idx);
            if self.selected >= self.order.len() && !self.order.is_empty() {
                self.selected = self.order.len() - 1;
            }
        }
        self.items.remove(id)
    }

    pub fn select_next(&mut self) {
        if self.selected + 1 < self.order.len() {
            self.selected += 1;
        }
    }

    pub fn select_prev(&mut self) {
        if self.selected > 0 {
            self.selected -= 1;
        }
    }

    pub fn selected(&self) -> Option<&PendingRequest> {
        self.order.get(self.selected).and_then(|id| self.items.get(id))
    }

    pub fn selected_mut(&mut self) -> Option<&mut PendingRequest> {
        let id = self.order.get(self.selected)?.clone();
        self.items.get_mut(&id)
    }

    pub fn selected_id(&self) -> Option<String> {
        self.order.get(self.selected).cloned()
    }

    pub fn selected_index(&self) -> usize {
        self.selected
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &PendingRequest)> {
        self.order
            .iter()
            .filter_map(move |id| self.items.get(id).map(|r| (id.as_str(), r)))
    }

    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }

    pub fn len(&self) -> usize {
        self.order.len()
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut PendingRequest> {
        self.items.get_mut(id)
    }

    /// Reload any request files already present in `request_dir` that we
    /// don't have in our seen set yet. Called once on startup and on the
    /// rare resync trigger.
    pub fn reload_from_dir(&mut self, request_dir: &Path) -> Result<usize> {
        let mut count = 0;
        let entries = match std::fs::read_dir(request_dir) {
            Ok(e) => e,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(0),
            Err(e) => return Err(e).context("reading request dir")?,
        };
        let mut paths: Vec<PathBuf> = entries
            .filter_map(|r| r.ok())
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| !n.starts_with('.') && n.ends_with(".json"))
            })
            .collect();
        // Deterministic FIFO order by filename (which is nanos.pid).
        paths.sort();
        for p in paths {
            match self.try_enqueue(p) {
                Ok(Some(_)) => count += 1,
                Ok(None) => {}
                Err(e) => eprintln!("approval-tui: failed to enqueue: {e:#}"),
            }
        }
        Ok(count)
    }
}

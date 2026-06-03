use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub broker_root: PathBuf,
    pub audit_log: PathBuf,
    pub gh_pat_file: Option<PathBuf>,
}

impl Config {
    pub fn from_env() -> Self {
        let broker_root = env::var("BOX_BROKER_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/tmp/box-broker"));
        let audit_log = env::var("BOX_AUDIT_LOG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/data/.state/approval-tui/audit.log"));
        let gh_pat_file = env::var("BOX_GH_PAT_FILE").ok().map(PathBuf::from);
        Self {
            broker_root,
            audit_log,
            gh_pat_file,
        }
    }

    pub fn request_dir(&self) -> PathBuf {
        self.broker_root.join("request")
    }

    pub fn response_dir(&self) -> PathBuf {
        self.broker_root.join("response")
    }

    pub fn agent_events_dir(&self) -> PathBuf {
        self.broker_root.join("agent-events")
    }
}

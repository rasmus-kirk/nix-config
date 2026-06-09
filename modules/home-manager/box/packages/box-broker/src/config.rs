use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub broker_root: PathBuf,
    pub audit_log: PathBuf,
    pub gh_pat_file: Option<PathBuf>,
    pub linear_pat_file: Option<PathBuf>,
    pub claude_projects_dir: PathBuf,
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
        let linear_pat_file = env::var("BOX_LINEAR_PAT_FILE").ok().map(PathBuf::from);
        let claude_projects_dir = env::var("BOX_CLAUDE_PROJECTS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
                PathBuf::from(home).join(".claude").join("projects")
            });
        Self {
            broker_root,
            audit_log,
            gh_pat_file,
            linear_pat_file,
            claude_projects_dir,
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

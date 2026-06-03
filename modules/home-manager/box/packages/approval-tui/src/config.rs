use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub broker_root: PathBuf,
    pub signing_key: PathBuf,
    pub audit_log: PathBuf,
}

impl Config {
    pub fn from_env() -> Self {
        let broker_root = env::var("BOX_BROKER_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/tmp/box-broker"));
        let signing_key = env::var("BOX_SIGNING_KEY")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/data/.secret/ssh/id_ed25519_yubi"));
        let audit_log = env::var("BOX_AUDIT_LOG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/data/.state/approval-tui/audit.log"));
        Self {
            broker_root,
            signing_key,
            audit_log,
        }
    }

    pub fn request_dir(&self) -> PathBuf {
        self.broker_root.join("request")
    }

    pub fn response_dir(&self) -> PathBuf {
        self.broker_root.join("response")
    }
}

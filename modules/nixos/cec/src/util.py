import subprocess
import threading

POLL = 1.0

def info(msg):
    """Writes msg to the journal. Use it only for actions and CEC results, never for key contents."""
    print(f"[cec] {msg}", flush=True)

def debug(cfg, msg):
    """Writes msg to the journal if cfg.debug is on."""
    if cfg.debug:
        info(msg)

def run(cmd, **kwargs):
    """Runs cmd and returns the completed process with stdout and stderr as text."""
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)

def quiet(cmd, **kwargs):
    """Runs cmd and discards its output."""
    return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)

def output(p):
    """Returns the stdout and stderr of p as one lowercase string."""
    return ((p.stdout or "") + (p.stderr or "")).lower()

def start(target):
    """Runs target in a daemon thread."""
    threading.Thread(target=target, daemon=True).start()

import filecmp
import json
import os
import shutil
import subprocess
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

import typer
import vdf

app = typer.Typer(help="Applies declared non-Steam shortcuts and their artwork to Steam.")

NON_STEAM_BIT = 0x80000000
SIGNED_OFFSET = 0x100000000
ART_SUFFIXES = {
    "portrait": "p",
    "landscape": "",
    "hero": "_hero",
    "logo": "_logo",
    "icon": "_icon",
}
DEFAULTS = {
    "icon": "",
    "ShortcutPath": "",
    "LaunchOptions": "",
    "IsHidden": 0,
    "AllowDesktopConfig": 1,
    "AllowOverlay": 1,
    "OpenVR": 0,
    "Devkit": 0,
    "DevkitGameID": "",
    "DevkitOverrideAppID": 0,
    "LastPlayTime": 0,
    "FlatpakAppID": "",
    "tags": {},
}


@dataclass(frozen=True)
class Shortcut:
    """One kirk.steamShortcuts.shortcuts entry. Nix expands the string shorthand to this form."""

    exe: str
    launchOptions: str
    icon: str | None
    portrait: str | None
    landscape: str | None
    hero: str | None
    logo: str | None


@dataclass(frozen=True)
class Config:
    """The kirk.steamShortcuts options, as the JSON file that Nix writes."""

    pruneUnmanaged: bool
    steamRoot: str
    shortcuts: dict[str, Shortcut]

    @classmethod
    def from_json(cls, text):
        """Makes a Config from JSON text. Unknown or missing keys raise TypeError."""
        data = json.loads(text)
        data["shortcuts"] = {name: Shortcut(**s) for name, s in data["shortcuts"].items()}
        return cls(**data)


def info(msg):
    """Writes msg to the journal."""
    print(f"steam-shortcuts: {msg}", flush=True)


def steam_running():
    """Returns True if a Steam process runs."""
    return subprocess.run(["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL).returncode == 0


def appid(name, shortcut):
    """
    Returns the unsigned 32-bit appid that Steam computes for a non-Steam shortcut. Grid file
    names use this value, and shortcuts.vdf stores it as a signed int32.
    """
    return (zlib.crc32((shortcut.exe + name).encode("utf-8")) & 0xFFFFFFFF) | NON_STEAM_BIT


def install_art(grid, aid, src, suffix):
    """
    Copies the image src into grid as <aid><suffix><ext> if the copy is missing or different.
    Returns the destination path, or None if src is None.
    """
    if not src:
        return None
    src = Path(src)
    dest = grid / f"{aid}{suffix}{src.suffix or '.png'}"
    if not dest.exists() or not filecmp.cmp(src, dest, shallow=False):
        shutil.copyfile(src, dest)
        dest.chmod(0o644)
        info(f"installed art {dest.name}")
    return dest


def managed_entry(grid, name, shortcut, existing):
    """
    Returns the shortcuts.vdf entry for a declared shortcut and installs its art. Sets appid,
    AppName, Exe, StartDir, LaunchOptions and icon, and keeps all other fields of existing.
    """
    aid = appid(name, shortcut)
    art = {kind: install_art(grid, aid, getattr(shortcut, kind), suffix) for kind, suffix in ART_SUFFIXES.items()}
    entry = dict(existing)
    for key, value in DEFAULTS.items():
        entry.setdefault(key, value)
    entry["appid"] = aid - SIGNED_OFFSET
    entry["AppName"] = name
    entry["Exe"] = f'"{shortcut.exe}"'
    entry["StartDir"] = f'"{os.path.dirname(shortcut.exe)}"'
    entry["LaunchOptions"] = shortcut.launchOptions
    if art["icon"]:
        entry["icon"] = str(art["icon"])
    return entry


def load(path):
    """Returns the contents of the binary VDF file at path, or an empty dict if it does not exist."""
    if not path.exists():
        return {}
    with path.open("rb") as f:
        return vdf.binary_load(f)


def apply(config_dir, cfg):
    """
    Writes the declared shortcuts to the shortcuts.vdf of one Steam account. With pruneUnmanaged,
    the file holds exactly the declared shortcuts. Without it, undeclared shortcuts stay. Backs up
    the old file before a write, and does not write a file that is already up to date.
    """
    path = config_dir / "shortcuts.vdf"
    grid = config_dir / "grid"
    grid.mkdir(exist_ok=True)
    data = load(path)
    current = data.get("shortcuts", {})
    by_name = {entry.get("AppName"): entry for entry in current.values()}
    managed = {name: managed_entry(grid, name, s, by_name.get(name, {})) for name, s in cfg.shortcuts.items()}
    kept = [] if cfg.pruneUnmanaged else [e for e in current.values() if e.get("AppName") not in managed]
    shortcuts = {str(i): entry for i, entry in enumerate([*kept, *managed.values()])}
    if shortcuts == current:
        info(f"{path} already up to date")
        return
    if path.exists():
        shutil.copy2(path, path.with_name(path.name + ".bak"))
    data["shortcuts"] = shortcuts
    with path.open("wb") as f:
        vdf.binary_dump(data, f)
    info(f"updated {path}" + (" (pruned to declared set)" if cfg.pruneUnmanaged else ""))


@app.command()
def main(config: Annotated[Path, typer.Argument(exists=True, dir_okay=False, help="JSON settings file.")]):
    """
    Applies the shortcuts in CONFIG, the kirk.steamShortcuts options as JSON, to the
    shortcuts.vdf of every Steam account under steamRoot.

    Steam reads shortcuts.vdf at start and writes it again on exit, so this does nothing while
    Steam runs. The systemd unit runs it before Steam starts.

    Each shortcut gets the appid that Steam computes from its exe and name. Its artwork goes to
    userdata/<id>/config/grid under that appid. On an existing entry with the same name, only
    the fields that managed_entry sets change.
    """
    if steam_running():
        info("Steam is running, skipping (applies next boot)")
        return
    cfg = Config.from_json(config.read_text())
    config_dirs = sorted(Path(cfg.steamRoot).glob("userdata/*/config"))
    if not config_dirs:
        info("no Steam userdata yet (log into Steam once first)")
        return
    for config_dir in config_dirs:
        apply(config_dir, cfg)


if __name__ == "__main__":
    app()

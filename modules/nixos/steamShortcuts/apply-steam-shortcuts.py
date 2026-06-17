#!/usr/bin/env python3
"""Apply declared non-Steam shortcuts (+ artwork) to every Steam account's
shortcuts.vdf. Invoked by the steam-shortcuts systemd service.

argv[1] = JSON: { "prune": bool,
                  "shortcuts": { "<AppName>": {exe, launchOptions, icon,
                                               portrait, landscape, hero, logo} } }
argv[2] = Steam data root (contains userdata/<id>/config/{shortcuts.vdf,grid/})

Owns these fields per declared shortcut: appid, Exe, StartDir, LaunchOptions,
icon (other fields on an existing entry are preserved). With prune=true the file
is rebuilt to contain *exactly* the declared shortcuts (removes undeclared ones
and de-duplicates). Backs up before writing; refuses to run while Steam is up
(Steam rewrites shortcuts.vdf on exit)."""
import filecmp
import glob
import json
import os
import shutil
import subprocess
import sys
import zlib

import vdf

cfg_file, steam_root = sys.argv[1], sys.argv[2]

if subprocess.run(["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL).returncode == 0:
    print("steam-shortcuts: Steam is running; skipping (applies next boot).")
    sys.exit(0)

with open(cfg_file) as f:
    cfg = json.load(f)
prune = cfg.get("prune", False)
desired = cfg["shortcuts"]

DEFAULTS = {
    "icon": "", "ShortcutPath": "", "LaunchOptions": "", "IsHidden": 0,
    "AllowDesktopConfig": 1, "AllowOverlay": 1, "OpenVR": 0, "Devkit": 0,
    "DevkitGameID": "", "DevkitOverrideAppID": 0, "LastPlayTime": 0,
    "FlatpakAppID": "", "tags": {},
}


def appid_unsigned(exe, name):
    """Steam's non-Steam appid (unsigned 32-bit) — grid filenames; stored signed."""
    return (zlib.crc32((exe + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def install_art(grid, aid, src, suffix):
    if not src:
        return None
    ext = os.path.splitext(src)[1] or ".png"
    dest = os.path.join(grid, f"{aid}{suffix}{ext}")
    if not os.path.exists(dest) or not filecmp.cmp(src, dest, shallow=False):
        shutil.copyfile(src, dest)
        os.chmod(dest, 0o644)  # store sources are read-only
        print(f"steam-shortcuts: installed art {os.path.basename(dest)}")
    return dest


configs = glob.glob(os.path.join(steam_root, "userdata", "*", "config"))
if not configs:
    print("steam-shortcuts: no Steam userdata yet (log into Steam once first).")
    sys.exit(0)

for cfgdir in configs:
    path = os.path.join(cfgdir, "shortcuts.vdf")
    grid = os.path.join(cfgdir, "grid")
    os.makedirs(grid, exist_ok=True)

    data = vdf.binary_load(open(path, "rb")) if os.path.exists(path) else {}
    sc = data.get("shortcuts", {})
    byname = {v.get("AppName"): v for v in sc.values()}

    # Build the managed entry for each declared shortcut: install its art, set
    # the owned fields, and keep any other fields from an existing same-name entry.
    managed = {}
    for name, s in desired.items():
        exe = s["exe"]
        aid = appid_unsigned(exe, name)
        install_art(grid, aid, s.get("portrait"), "p")
        install_art(grid, aid, s.get("landscape"), "")
        install_art(grid, aid, s.get("hero"), "_hero")
        install_art(grid, aid, s.get("logo"), "_logo")
        icon_dest = install_art(grid, aid, s.get("icon"), "_icon")

        entry = dict(byname.get(name, {}))
        for k, v in DEFAULTS.items():
            entry.setdefault(k, v)
        entry["appid"] = aid - 0x100000000  # signed int32
        entry["AppName"] = name
        entry["Exe"] = '"' + exe + '"'
        entry["StartDir"] = '"' + os.path.dirname(exe) + '"'
        entry["LaunchOptions"] = s.get("launchOptions", "")
        if icon_dest:
            entry["icon"] = icon_dest
        managed[name] = entry

    if prune:
        # Authoritative: exactly the declared shortcuts, nothing else.
        new_list = list(managed.values())
    else:
        # Keep undeclared entries; replace/add the managed ones.
        new_list = [v for v in sc.values() if v.get("AppName") not in managed]
        new_list += list(managed.values())

    new_sc = {str(i): e for i, e in enumerate(new_list)}

    if new_sc == sc:
        print(f"steam-shortcuts: {path} already up to date")
        continue
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak")
    data["shortcuts"] = new_sc
    with open(path, "wb") as f:
        vdf.binary_dump(data, f)
    print(f"steam-shortcuts: updated {path}{' (pruned to declared set)' if prune else ''}")

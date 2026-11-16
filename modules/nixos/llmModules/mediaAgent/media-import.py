import fcntl
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath

import magic

FICLONE = 0x40049409
HASH = re.compile(r"[0-9a-f]{40}")


class Rejected(Exception):
    pass


class Incomplete(Exception):
    pass


def relative(value):
    if not isinstance(value, str) or not value or "\0" in value:
        raise Rejected(f"not a path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise Rejected(f"unsafe path: {value}")
    return path


def plan(config, manifest):
    files = manifest.get("files") if isinstance(manifest, dict) else None
    if not isinstance(files, list) or not files:
        raise Rejected('manifest is not {"files": [{"from": ..., "to": ...}]}')
    torrents = Path(config["torrents"])
    library = Path(config["library"])
    pairs = []
    seen = set()
    for entry in files:
        if not isinstance(entry, dict):
            raise Rejected(f"not a from/to entry: {entry!r}")
        source = relative(entry.get("from"))
        target = relative(entry.get("to"))
        src = torrents / source
        dst = library / target
        ext = target.suffix[1:].lower()
        mimes = config["allowed"].get(ext)
        if mimes is None:
            raise Rejected(f"extension not allowed: {target}")
        if target in seen or dst.exists() or dst.is_symlink():
            raise Rejected(f"target exists: {target}")
        seen.add(target)
        if src.is_symlink():
            raise Rejected(f"source is a symlink: {source}")
        if not src.is_file():
            raise Incomplete(f"{source} missing")
        mime = magic.from_file(str(src), mime=True)
        if mime not in mimes:
            raise Rejected(f"content {mime} does not match .{ext}: {source}")
        pairs.append((src, dst))
    return pairs


def reflink(src, dst):
    with open(src, "rb") as s, open(dst, "xb") as d:
        try:
            fcntl.ioctl(d.fileno(), FICLONE, s.fileno())
        except OSError:
            os.unlink(dst)
            raise


def link(mode, src, dst):
    if mode == "hardlink":
        os.link(src, dst)
    else:
        reflink(src, dst)


def run(config, hash):
    agent = Path(config["agent"])
    manifest = agent / f"{hash}.json"
    if not manifest.is_file():
        print(f"{hash} has no manifest", file=sys.stderr)
        return
    try:
        pairs = plan(config, json.loads(manifest.read_text()))
        for src, dst in pairs:
            dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                link(config["linkMode"], src, dst)
            except OSError as e:
                raise Rejected(f"{config['linkMode']} failed: {dst}: {e}")
    except Incomplete as e:
        print(f"{hash} incomplete, {e}", file=sys.stderr)
        return
    except (Rejected, OSError, ValueError) as e:
        print(f"{hash} rejected: {e}", file=sys.stderr)
        (agent / "rejected" / f"{hash}.reason").write_text(f"{e}\n")
        manifest.rename(agent / "rejected" / f"{hash}.json")
        return
    manifest.rename(agent / "done" / f"{hash}.json")
    print(f"{hash} imported {len(pairs)} files", flush=True)


def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    os.umask(0o002)
    for entry in sorted(Path(config["queue"]).iterdir()):
        entry.unlink()
        if HASH.fullmatch(entry.name):
            run(config, entry.name)
        else:
            print(f"ignoring queue entry {entry.name}", file=sys.stderr)


if __name__ == "__main__":
    main()

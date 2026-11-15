import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from itertools import count
from pathlib import Path, PurePosixPath
from typing import Literal

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError

CONFIG = json.loads(Path(sys.argv[1]).read_text())
AGENT = Path(CONFIG["agent"])
LIBRARY = Path(CONFIG["library"])
ALLOWED = set(CONFIG["allowed"])
CREDENTIALS = Path(os.environ["CREDENTIALS_DIRECTORY"])
PROWLARR_KEY = (CREDENTIALS / "prowlarr").read_text().strip()

Kind = Literal["movie", "show", "music", "audiobook", "ebook"]
CATEGORIES = {
    "movie": 2000,
    "show": 5000,
    "music": 3000,
    "audiobook": 3030,
    "ebook": 7020,
}
VIDEO = {"mkv", "mp4", "m4v", "avi"}
SUBTITLE = {"srt", "ass", "ssa", "vtt", "sub", "idx"}
AUDIO = {"flac", "mp3", "m4a", "m4b", "opus", "ogg"}
BOOK = {"epub", "pdf", "mobi", "azw3"}
IMAGE = {"jpg", "png"}
MEDIA = VIDEO | SUBTITLE | AUDIO | BOOK | IMAGE
KEEP = {
    "movie": VIDEO | SUBTITLE,
    "show": VIDEO | SUBTITLE,
    "music": AUDIO | IMAGE,
    "audiobook": AUDIO | IMAGE,
    "ebook": BOOK,
}
DANGEROUS = {
    "exe", "msi", "scr", "com", "pif", "cpl", "dll", "bat", "cmd", "ps1",
    "vbs", "vbe", "js", "jse", "wsf", "wsh", "hta", "jar", "sh", "py",
    "pl", "rb", "apk", "app", "dmg", "deb", "rpm", "lnk", "desktop",
    "reg", "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst",
    "iso", "img", "cab", "arj", "lzh",
}
SPLIT_ARCHIVE = re.compile(r"r\d\d|\d{3}")
EPISODE = re.compile(
    r"(?<![a-z0-9])s(\d{1,2})[ ._-]?e(\d{1,3})(?:[ ._-]?e?(\d{1,3})\b)?"
    r"|\b(\d{1,2})x(\d{2,3})\b",
    re.IGNORECASE,
)
HASH = re.compile(r"[0-9a-f]{40}")
LANGUAGES = {
    "en": "en", "eng": "en", "english": "en",
    "da": "da", "dan": "da", "danish": "da", "dansk": "da",
    "sv": "sv", "swe": "sv", "swedish": "sv",
    "nb": "no", "nor": "no", "norwegian": "no",
    "de": "de", "ger": "de", "deu": "de", "german": "de",
    "fr": "fr", "fre": "fr", "fra": "fr", "french": "fr",
    "es": "es", "spa": "es", "spanish": "es",
    "it": "it", "ita": "it", "italian": "it",
    "nl": "nl", "dut": "nl", "nld": "nl", "dutch": "nl",
    "fi": "fi", "fin": "fi", "finnish": "fi",
    "pt": "pt", "por": "pt", "portuguese": "pt",
    "ja": "ja", "jpn": "ja", "japanese": "ja",
    "zh": "zh", "chi": "zh", "zho": "zh", "chinese": "zh",
    "ru": "ru", "rus": "ru", "russian": "ru",
    "pl": "pl", "pol": "pl", "polish": "pl",
}
MAX_TORRENT = 8 * 1024 * 1024
METADATA_TIMEOUT = 120
MAX_RELEASES = 1000
RELEASES = {}
RELEASE_IDS = count(1)
SESSION = {"id": ""}

server = MCPServer(
    "media",
    instructions=Path(CONFIG["instructions"]).read_text(),
)


def tool(fn):
    return server.tool(structured_output=False)(fn)


def dumps(value):
    return json.dumps(value, ensure_ascii=False)


def get_json(url, headers=None, timeout=60):
    host = urllib.parse.urlsplit(url).netloc
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise ToolError(f"{host} answered HTTP {error.code}")
    except OSError as error:
        raise ToolError(f"{host} failed, {error}")
    except ValueError:
        raise ToolError(f"{host} sent no JSON")


def tmdb(path, **params):
    query = urllib.parse.urlencode({"api_key": CONFIG["tmdbKey"], **params})
    return get_json(f"https://api.themoviedb.org/3/{path}?{query}")


def prowlarr_search(kind, search_type, text):
    query = urllib.parse.urlencode({
        "query": text,
        "type": search_type,
        "categories": CATEGORIES[kind],
        "limit": 100,
    })
    results = get_json(
        f"{CONFIG['prowlarr']}/api/v1/search?{query}",
        {"X-Api-Key": PROWLARR_KEY},
        timeout=120,
    )
    return [r for r in results if r.get("protocol") == "torrent"]


def rpc(method, arguments):
    url = f"http://{CONFIG['transmission']}/transmission/rpc"
    body = json.dumps({"method": method, "arguments": arguments}).encode()
    for _ in range(2):
        request = urllib.request.Request(url, body, {
            "Content-Type": "application/json",
            "X-Transmission-Session-Id": SESSION["id"],
        })
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                reply = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 409:
                SESSION["id"] = error.headers.get(
                    "X-Transmission-Session-Id", ""
                )
                continue
            raise ToolError(f"Transmission answered HTTP {error.code}")
        except OSError as error:
            raise ToolError(f"Transmission failed, {error}")
        if reply.get("result") != "success":
            raise ToolError(f"Transmission: {reply.get('result')}")
        return reply.get("arguments", {})
    raise ToolError("Transmission refused the session id")


def torrent(torrent_hash, fields):
    found = rpc("torrent-get", {"ids": [torrent_hash], "fields": fields})
    if not found.get("torrents"):
        raise ToolError(f"Transmission has no torrent {torrent_hash}")
    return found["torrents"][0]


def remove(torrent_hash):
    rpc("torrent-remove", {"ids": [torrent_hash], "delete-local-data": True})


def add(arguments):
    reply = rpc("torrent-add", arguments)
    if "torrent-duplicate" in reply:
        existing_hash = reply["torrent-duplicate"]["hashString"]
        raise ToolError(f"Transmission already has torrent {existing_hash}")
    return reply["torrent-added"]["hashString"]


def wait_for_files(torrent_hash):
    deadline = time.monotonic() + METADATA_TIMEOUT
    while time.monotonic() < deadline:
        files = torrent(torrent_hash, ["files"])["files"]
        if files:
            return files
        time.sleep(2)
    remove(torrent_hash)
    raise ToolError(
        f"the magnet found no metadata in {METADATA_TIMEOUT} seconds, "
        "removed the torrent"
    )


def bdecode(data):
    def parse(index, depth):
        if depth > 32:
            raise ValueError("nested too deep")
        head = data[index:index + 1]
        if head == b"i":
            end = data.index(b"e", index)
            return int(data[index + 1:end]), end + 1
        if head in (b"l", b"d"):
            index += 1
            items = []
            while data[index:index + 1] != b"e":
                item, index = parse(index, depth + 1)
                items.append(item)
            if head == b"l":
                return items, index + 1
            return dict(zip(items[::2], items[1::2])), index + 1
        if head.isdigit():
            colon = data.index(b":", index)
            end = colon + 1 + int(data[index:colon])
            if end > len(data):
                raise ValueError("string past the end")
            return data[colon + 1:end], end
        raise ValueError(f"unexpected byte at {index}")

    value, _ = parse(0, 0)
    return value


def torrent_files(data):
    info = bdecode(data)[b"info"]
    name = (info.get(b"name.utf-8") or info[b"name"]).decode()
    if b"files" not in info:
        return [(name, info[b"length"])]
    files = []
    for entry in info[b"files"]:
        if b"p" in entry.get(b"attr", b""):
            continue
        parts = entry.get(b"path.utf-8") or entry[b"path"]
        path = "/".join([name, *(part.decode() for part in parts)])
        files.append((path, entry[b"length"]))
    return files


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def fetch(release):
    url = release["download_url"] or release["magnet_url"]
    for _ in range(5):
        if not url:
            raise ToolError("the release has no download link")
        if url.startswith("magnet:"):
            return None, url
        try:
            with OPENER.open(url, timeout=60) as response:
                data = response.read(MAX_TORRENT + 1)
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise ToolError(f"the download answered HTTP {error.code}")
            url = urllib.parse.urljoin(url, error.headers.get("Location"))
            continue
        except OSError as error:
            raise ToolError(f"the download failed, {error}")
        if len(data) > MAX_TORRENT:
            raise ToolError("the torrent file is over 8 MB")
        return data, None
    raise ToolError("the download redirected too often")


def extension(path):
    return PurePosixPath(path).suffix[1:].lower()


def inner(path):
    return path.split("/", 1)[-1]


def check(files):
    if not files:
        return "the torrent has no files"
    for path, _ in files:
        parts = PurePosixPath(path).parts
        if path.startswith("/") or "\0" in path or {".", ".."} & set(parts):
            return f"unsafe path {path}"
        extensions = PurePosixPath(path).name.lower().split(".")[1:]
        if not extensions:
            continue
        last = extensions[-1]
        if last in DANGEROUS or SPLIT_ARCHIVE.fullmatch(last):
            return f"{path} is an executable, script, shortcut or archive"
        if len(extensions) > 1 and extensions[-2] in MEDIA and (
            last not in MEDIA
        ):
            return f"{path} has a double extension"
    return None


def episode(path):
    for text in (PurePosixPath(path).name, path):
        match = EPISODE.search(text)
        if not match:
            continue
        if match[4]:
            return int(match[4]), int(match[5]), None
        first = int(match[2])
        last = int(match[3]) if match[3] else None
        return int(match[1]), first, last if last and last > first else None
    return None


def subtitle_suffix(path):
    words = re.split(r"[^a-z0-9]+", path.lower())
    language = next(
        (LANGUAGES[word] for word in reversed(words) if word in LANGUAGES),
        None,
    )
    tags = [language] + [tag for tag in ("sdh", "forced") if tag in words]
    return "".join(f".{tag}" for tag in tags if tag)


def clean(text):
    text = re.sub(r"[/:\x00-\x1f]", "-", text).strip()
    if text in ("", ".", ".."):
        raise ToolError(f"unusable name {text!r}")
    return text


def named(title, year):
    return f"{title} ({year})" if year else title


def existing(parent, match):
    folder = LIBRARY / parent
    if folder.is_dir():
        for entry in sorted(folder.iterdir()):
            if entry.is_dir() and match(entry.name):
                return entry.name
    return None


def same(name):
    return lambda entry: entry.casefold() == name.casefold()


class Plan:
    def __init__(self):
        self.kept = []
        self.skipped = Counter()
        self.targets = set()

    def keep(self, source, target):
        if target in self.targets:
            self.skipped["duplicate"] += 1
        elif (LIBRARY / target).exists():
            self.skipped["already in library"] += 1
        else:
            self.targets.add(target)
            self.kept.append({"from": source, "to": target})


def plan_movie(target, media, result):
    tag = f"[tmdbid-{target['tmdb_id']}]"
    base = f"{named(target['title'], target['year'])} {tag}"
    folder = existing("movies", lambda name: name.endswith(tag)) or base
    videos = [path for path, ext in media if ext in VIDEO]
    for index, path in enumerate(videos):
        if index:
            result.skipped["extra video"] += 1
        else:
            result.keep(path, f"movies/{folder}/{base}.{extension(path)}")
    for path, ext in media:
        if ext not in SUBTITLE:
            continue
        if not videos:
            result.skipped["subtitle without video"] += 1
            continue
        suffix = subtitle_suffix(path)
        result.keep(path, f"movies/{folder}/{base}{suffix}.{ext}")


def plan_show(target, media, result):
    tag = f"[tmdbid-{target['tmdb_id']}]"
    base = f"{named(target['title'], target['year'])} {tag}"
    folder = existing("shows", lambda name: name.endswith(tag)) or base
    stems = set()
    for path, ext in media:
        found = episode(path)
        if not found:
            result.skipped["no episode number"] += 1
            continue
        season, first, last = found
        if target["season"] is not None and season != target["season"]:
            result.skipped["other season"] += 1
            continue
        if max(first, last or 0) > target["episodes"].get(season, 0):
            result.skipped["episode not on TMDB"] += 1
            continue
        code = f"S{season:02}E{first:02}" + (f"-E{last:02}" if last else "")
        stem = f"shows/{folder}/Season {season:02}/{target['title']} {code}"
        if ext in VIDEO:
            stems.add(stem)
            result.keep(path, f"{stem}.{ext}")
        elif stem in stems:
            result.keep(path, f"{stem}{subtitle_suffix(path)}.{ext}")
        else:
            result.skipped["subtitle without episode"] += 1


def plan_music(target, media, result):
    artist = existing("music", same(target["artist"])) or target["artist"]
    album = named(target["album"], target["year"])
    for path, _ in media:
        result.keep(path, f"music/{artist}/{album}/{inner(path)}")


def plan_audiobook(target, media, result):
    author = existing("audiobooks", same(target["author"]))
    folder = f"audiobooks/{author or target['author']}/{target['title']}"
    for path, _ in media:
        result.keep(path, f"{folder}/{inner(path)}")


def plan_ebook(target, media, result):
    author = existing("books", same(target["author"])) or target["author"]
    title = target["title"]
    for path, ext in media:
        result.keep(path, f"books/{author}/{title}/{title}.{ext}")


PLANNERS = {
    "movie": plan_movie,
    "show": plan_show,
    "music": plan_music,
    "audiobook": plan_audiobook,
    "ebook": plan_ebook,
}


def plan(target, files):
    kind = target["kind"]
    result = Plan()
    media = []
    for path, size in files:
        ext = extension(path)
        if ext not in KEEP[kind] or ext not in ALLOWED:
            result.skipped[f"not {kind} media"] += 1
        elif "sample" in inner(path).lower():
            result.skipped["sample"] += 1
        else:
            media.append((ext in SUBTITLE, -size, path, ext))
    media.sort()
    PLANNERS[kind](target, [(path, ext) for *_, path, ext in media], result)
    return result


def size_text(size):
    if size >= 1e9:
        return f"{size / 1e9:.1f} GB"
    return f"{size / 1e6:.0f} MB"


def summary(release):
    keys = ("release_id", "title", "size", "seeders", "indexer")
    return {key: release[key] for key in keys}


def inspect(release_id):
    release = RELEASES.get(release_id)
    if release is None:
        return {"release_id": release_id, "verdict": "unknown, search again"}
    result = summary(release)
    try:
        if "torrent" not in release:
            release["torrent"], release["magnet"] = fetch(release)
    except ToolError as error:
        return result | {"verdict": f"rejected, {error}"}
    if release["torrent"] is None:
        return result | {
            "source": "magnet",
            "verdict": "ok, the files are checked when you add it",
        }
    result["source"] = "torrent file"
    try:
        files = torrent_files(release["torrent"])
    except (ValueError, KeyError, TypeError, AttributeError):
        return result | {"verdict": "rejected, broken torrent file"}
    reason = check(files)
    if reason:
        return result | {"verdict": f"rejected, {reason}"}
    planned = plan(release["target"], files)
    paths = [entry["to"] for entry in planned.kept]
    if len(paths) > 20:
        paths = paths[:20] + [f"and {len(paths) - 20} more"]
    return result | {
        "verdict": "ok" if planned.kept else "nothing to import",
        "files": paths,
        "skipped": dict(planned.skipped),
    }


def rank(entry):
    sources = {"torrent file": 0, "magnet": 1}
    return (
        not entry["verdict"].startswith("ok"),
        sources.get(entry.get("source"), 2),
        -entry.get("seeders", 0),
    )


def finish(torrent_hash, release, files):
    files = [(entry["name"], entry["length"]) for entry in files]
    reason = check(files)
    kept = [] if reason else plan(release["target"], files).kept
    if not kept:
        remove(torrent_hash)
        raise ToolError(
            f"rejected, {reason or 'nothing to import'}, removed the torrent"
        )
    manifest = AGENT / f"{torrent_hash}.json"
    manifest.write_text(json.dumps({"files": kept}, indent=2) + "\n")
    wanted = {entry["from"] for entry in kept}
    unwanted = [i for i, (name, _) in enumerate(files) if name not in wanted]
    if unwanted:
        rpc("torrent-set", {"ids": [torrent_hash], "files-unwanted": unwanted})
    rpc("torrent-start", {"ids": [torrent_hash]})
    done = torrent(torrent_hash, ["percentDone"])["percentDone"] >= 1
    if done:
        (AGENT / "queue" / torrent_hash).touch()
    return dumps({
        "hash": torrent_hash,
        "state": "importing" if done else "downloading",
        "files": [entry["to"] for entry in kept],
    })


def target_for(kind, tmdb_id, season, artist, album, author, title, year):
    if kind == "movie":
        if tmdb_id is None:
            raise ToolError("a movie needs tmdb_id")
        data = tmdb(f"movie/{tmdb_id}", append_to_response="external_ids")
        released = (data.get("release_date") or "")[:4] or None
        imdb = (data.get("external_ids") or {}).get("imdb_id")
        searches = [("movie", f"{{ImdbId:{imdb}}}")] if imdb else []
        text = named(data["title"], released)
        target = {
            "kind": kind,
            "tmdb_id": tmdb_id,
            "title": clean(data["title"]),
            "year": released,
        }
        return target, searches + [("search", text)]
    if kind == "show":
        if tmdb_id is None:
            raise ToolError("a show needs tmdb_id")
        data = tmdb(f"tv/{tmdb_id}", append_to_response="external_ids")
        episodes = {
            entry["season_number"]: entry.get("episode_count") or 0
            for entry in data.get("seasons") or []
        }
        if season is not None and season not in episodes:
            raise ToolError(f"TMDB lists only seasons {sorted(episodes)}")
        ids = data.get("external_ids") or {}
        tag = f"{{Season:{season}}}" if season is not None else ""
        searches = []
        if ids.get("tvdb_id"):
            searches.append(("tvsearch", f"{{TvdbId:{ids['tvdb_id']}}}{tag}"))
        elif ids.get("imdb_id"):
            searches.append(("tvsearch", f"{{ImdbId:{ids['imdb_id']}}}{tag}"))
        text = data["name"] + (f" S{season:02}" if season is not None else "")
        target = {
            "kind": kind,
            "tmdb_id": tmdb_id,
            "title": clean(data["name"]),
            "year": (data.get("first_air_date") or "")[:4] or None,
            "season": season,
            "episodes": episodes,
        }
        return target, searches + [("search", text)]
    if kind == "music":
        if not artist or not album:
            raise ToolError("music needs artist and album")
        target = {
            "kind": kind,
            "artist": clean(artist),
            "album": clean(album),
            "year": year,
        }
        return target, [("search", f"{artist} {album}")]
    if not author or not title:
        raise ToolError(f"an {kind} needs author and title")
    target = {"kind": kind, "author": clean(author), "title": clean(title)}
    return target, [("search", f"{author} {title}")]


@tool
def search_library(text: str) -> str:
    """Find library folders and files whose name contains text.

    The match ignores case. Returns up to 50 paths relative to the library.
    Folders end with /.
    """
    needle = text.casefold()
    hits = []
    for root, folders, files in os.walk(LIBRARY):
        folders.sort()
        relative = Path(root).relative_to(LIBRARY)
        for name in folders + sorted(files):
            if needle in name.casefold():
                slash = "/" if name in folders else ""
                hits.append(f"{relative / name}{slash}")
                if len(hits) == 50:
                    return dumps(hits)
    return dumps(hits)


@tool
def list_library(path: str = "") -> str:
    """List one library folder.

    path is relative to the library, for example "shows" or
    "shows/Severance (2022) [tmdbid-95396]". Folders end with /.
    """
    relative = PurePosixPath(path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ToolError("path must stay inside the library")
    folder = LIBRARY / relative
    if not folder.is_dir():
        raise ToolError(f"{path} is not a library folder")
    entries = sorted(folder.iterdir())
    names = [entry.name + ("/" if entry.is_dir() else "") for entry in entries]
    return dumps(names[:500])


@tool
def tmdb_search(
    kind: Literal["movie", "show"], query: str, year: int | None = None
) -> str:
    """Look up a movie or show on TMDB. Returns up to 8 matches."""
    params = {"query": query}
    if year:
        params["year" if kind == "movie" else "first_air_date_year"] = year
    path = "movie" if kind == "movie" else "tv"
    results = tmdb(f"search/{path}", **params).get("results") or []
    return dumps([
        {
            "tmdb_id": entry["id"],
            "title": entry.get("title") or entry.get("name"),
            "year": (
                entry.get("release_date") or entry.get("first_air_date") or ""
            )[:4],
            "overview": (entry.get("overview") or "")[:200],
            "url": f"https://www.themoviedb.org/{path}/{entry['id']}",
        }
        for entry in results[:8]
    ])


@tool
def tmdb_show(tmdb_id: int) -> str:
    """List the seasons of a TMDB show with their episode counts."""
    data = tmdb(f"tv/{tmdb_id}")
    return dumps({
        "title": data.get("name"),
        "status": data.get("status"),
        "url": f"https://www.themoviedb.org/tv/{tmdb_id}",
        "seasons": [
            {
                "season": entry["season_number"],
                "episodes": entry.get("episode_count"),
                "air_date": entry.get("air_date"),
            }
            for entry in data.get("seasons") or []
        ],
    })


@tool
def search_releases(
    kind: Kind,
    tmdb_id: int | None = None,
    season: int | None = None,
    artist: str | None = None,
    album: str | None = None,
    author: str | None = None,
    title: str | None = None,
    year: int | None = None,
    query: str | None = None,
) -> str:
    """Search the torrent indexers. Returns releases, most seeders first.

    A movie needs tmdb_id. A show needs tmdb_id. Give season to get one
    season of a show. Music needs artist and album, and year if known.
    An audiobook or ebook needs author and title. If a search finds
    nothing, search again with query, the free text to send to the
    indexers.
    """
    target, searches = target_for(
        kind, tmdb_id, season, artist, album, author, title, year
    )
    if query:
        searches = [("search", query)]
    found = []
    for search_type, text in searches:
        found = prowlarr_search(kind, search_type, text)
        if found:
            break
    unique = {}
    for result in sorted(found, key=lambda r: -(r.get("seeders") or 0)):
        key = (result.get("infoHash") or result.get("title") or "").lower()
        unique.setdefault(key, result)
    releases = []
    for result in list(unique.values())[:20]:
        release_id = f"r{next(RELEASE_IDS)}"
        RELEASES[release_id] = {
            "release_id": release_id,
            "title": result.get("title"),
            "size": size_text(result.get("size") or 0),
            "seeders": result.get("seeders") or 0,
            "indexer": result.get("indexer"),
            "download_url": result.get("downloadUrl"),
            "magnet_url": result.get("magnetUrl"),
            "target": target,
        }
        releases.append(summary(RELEASES[release_id]))
    while len(RELEASES) > MAX_RELEASES:
        del RELEASES[next(iter(RELEASES))]
    return dumps(releases)


@tool
def inspect_releases(release_ids: list[str]) -> str:
    """Download and check the torrent files of up to ten releases.

    Returns the releases best first. For each release, verdict says if it
    is ok, files lists the library path of each file to import, and
    skipped counts the other files by reason. A magnet release shows its
    files only after add_release.
    """
    with ThreadPoolExecutor(5) as pool:
        results = list(pool.map(inspect, release_ids[:10]))
    return dumps(sorted(results, key=rank))


@tool
def add_release(release_id: str) -> str:
    """Download a release and queue its files for import into the library.

    Call this only after the user picked the release.
    """
    release = RELEASES.get(release_id)
    if release is None:
        raise ToolError("unknown release, search again")
    if "torrent" not in release:
        release["torrent"], release["magnet"] = fetch(release)
    if release["torrent"] is None:
        torrent_hash = add({"filename": release["magnet"], "paused": False})
        files = wait_for_files(torrent_hash)
    else:
        metainfo = base64.b64encode(release["torrent"]).decode()
        torrent_hash = add({"metainfo": metainfo, "paused": True})
        files = torrent(torrent_hash, ["files"])["files"]
    return finish(torrent_hash, release, files)


@tool
def status() -> str:
    """Show the downloads that wait for import and the latest imports.

    A rejected import shows its reason.
    """
    pending = sorted(path.stem for path in AGENT.glob("*.json"))
    torrents = {}
    if pending:
        fields = ["hashString", "name", "percentDone", "errorString"]
        reply = rpc("torrent-get", {"ids": pending, "fields": fields})
        torrents = {entry["hashString"]: entry for entry in reply["torrents"]}

    def latest(folder):
        paths = (AGENT / folder).glob("*.json")
        newest = sorted(paths, key=lambda p: p.stat().st_mtime, reverse=True)
        return newest[:10]

    def first_file(path):
        return json.loads(path.read_text())["files"][0]["to"]

    return dumps({
        "downloading": [
            {
                "hash": torrent_hash,
                "name": torrents.get(torrent_hash, {}).get("name"),
                "percent": round(
                    100 * torrents.get(torrent_hash, {}).get("percentDone", 0)
                ),
                "error": torrents.get(torrent_hash, {}).get("errorString"),
            }
            for torrent_hash in pending
        ],
        "imported": [
            {"hash": path.stem, "first_file": first_file(path)}
            for path in latest("done")
        ],
        "rejected": [
            {
                "hash": path.stem,
                "reason": path.with_suffix(".reason").read_text().strip(),
            }
            for path in latest("rejected")
            if path.with_suffix(".reason").exists()
        ],
    })


@tool
def remove_torrent(hash: str) -> str:
    """Delete a torrent and its downloaded data from Transmission.

    The files in the library stay.
    """
    if not HASH.fullmatch(hash):
        raise ToolError("hash must be 40 lowercase hex characters")
    remove(hash)
    (AGENT / f"{hash}.json").unlink(missing_ok=True)
    return "removed"


if __name__ == "__main__":
    server.run(
        "streamable-http",
        host="127.0.0.1",
        port=CONFIG["port"],
        stateless_http=True,
        json_response=True,
    )

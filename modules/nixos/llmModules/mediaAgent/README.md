# Media agent module

`kirk.llmModules.mediaAgent` runs `media-mcp`, an MCP (Model Context
Protocol) server on `127.0.0.1:8765`. Its tools find torrents through TMDB
and Prowlarr, check the files, choose the library paths and add the
torrents to Transmission. When a download finishes, `media-import` checks
the files again and links them into the library under Jellyfin and
Audiobookshelf names.

Any MCP client can use the tools. The module registers the server in Open
WebUI and links `.mcp.json` for Claude Code into the agent directory.

## Files

- `default.nix` holds the options, the Transmission done-script, the
  `media-mcp` and `media-import` services and the agent directory.
- `media-mcp.py` is the MCP server.
- `instructions.md` holds the workflow. The server sends it to each client,
  and the client adds it to the system prompt.
- `media-import.py` checks and links the files of each finished download.

## Setup

1. In Prowlarr, open Settings > General and copy the API key.
2. Run `RULES=./agenix-rules.nix agenix -e age/desktop/prowlarr-api-key.age` and paste the key.
3. Rebuild the system.

TMDB lookups use the TMDB API key that Jellyfin bundles in
`MediaBrowser.Providers/Plugins/Tmdb/TmdbUtils.cs`. `default.nix` holds a
copy. If Jellyfin replaces that key, update the copy.

## Use

In Open WebUI, every model has the media tools on by default, and every
approved account can use them. Ask for a movie, show, album, audiobook or
ebook.

To use Claude Code, run:

```sh
cd /data/media/.agent
box --net claude
```

`--net` shares the host network, so Claude reaches the MCP server. Claude
Code asks once whether to trust the server in `.mcp.json`.

## Tools

- `search_library` and `list_library` read the library.
- `tmdb_search` and `tmdb_show` look up movies and shows.
- `search_releases` searches Prowlarr by IMDb or TVDB ID first. If the ID
  search finds nothing, it searches by title.
- `inspect_releases` downloads the torrent files and plans the library path
  of each file. It rejects a release with an executable, a script, a
  shortcut, an archive or a double extension. It skips samples, other
  seasons, files already in the library and files of another media kind.
- `add_release` adds the torrent paused, writes the manifest, deselects the
  skipped files and starts the torrent. For a magnet, it waits up to two
  minutes for the file list and then runs the same checks.
- `status` lists the downloads that wait for import and the latest imports.
- `remove_torrent` deletes a torrent and its downloaded data.

## Import

1. `add_release` writes `<hash>.json`, which maps each file of the torrent
   to a library path.
2. When the torrent finishes, Transmission's done-script creates
   `queue/<hash>`.
3. A systemd path unit starts `media-import` as the `transmission` user. It
   handles every entry in `queue/`.
4. `media-import` checks every file in the manifest. The extension must be
   in the allowlist, the content type from libmagic must match the
   extension, and the target must not exist.
5. If every check passes, `media-import` links the files and moves the
   manifest to `done/`. Otherwise it moves the manifest to `rejected/` and
   writes the reason to `rejected/<hash>.reason`.

If a source file is still missing, `media-import` leaves the manifest in
place. To import a manifest again, run `touch /data/media/.agent/queue/<hash>`.

`linkMode` selects a reflink (the default) or a hardlink. Transmission keeps
seeding from its download directory in both modes.

Read the logs with `journalctl -u media-mcp` and `journalctl -u media-import`.

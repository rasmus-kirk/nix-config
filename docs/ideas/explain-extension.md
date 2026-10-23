# Idea: Explain selected text with Claude in the browser

## Context

Reading a paper, a PDF or a web page, a selected term or passage often
needs context that is not on the page. Copying it into claude.ai loses the
surrounding text and breaks the reading flow.

Model: a browser extension for Firefox and Chrome, from one Manifest V3
codebase in a new repo (`~/explain`). Select text, press the "Explain"
button or `Alt+E`, and a panel docked to the right edge of the page streams
Claude's answer. Follow-up questions in the panel keep the context.

- One mechanism for all pages. A content script reads the selection and the
  text around it. PDFs open in the extension's own PDF.js viewer, which
  renders an HTML text layer, so the same content script works there.
- The panel is a Shadow DOM element in the page. The browser side panels
  differ between Firefox and Chrome, and both open only from a direct user
  gesture, which a content script message is not.
- Claude runs through the local Claude Code CLI on the Max plan, not the
  API. A native messaging host starts `claude -p` for the extension, so
  there is no API bill.
- `claude` runs in its own bubblewrap sandbox with no tools. Page text is
  untrusted and can carry prompt injection. With `--tools ""` Claude can
  only write text, and the sandbox shows it only its own login. The
  sandbox follows `modules/home-manager/box/default.nix` but is a separate
  copy, because `box` only opens an interactive shell, writes activation
  output to stdout, and shares the Claude state that `claudeConfig` fills
  with `CLAUDE.md`, hooks and MCP servers.

Limits:

- Usage counts against the Max limits.
- Each new conversation starts a `claude` process, about 1 to 3 seconds
  before the first token.
- The sandbox network is open. bubblewrap cannot limit it to Anthropic's
  servers. The sandbox holds only the Claude login and the page text.
- `--bare` cannot replace the sandbox home. It reads only
  `ANTHROPIC_API_KEY` and never the Max OAuth login.
- Firefox extensions cannot read `file://`. Local PDFs open in Firefox by
  drag-and-drop or the file picker.
- Firefox and Chromium from Snap or Flatpak cannot start native hosts.

## Changes

- `manifests/base.json`: permissions `storage`, `webRequest`, `tabs`,
  `nativeMessaging`, host permission `<all_urls>`, the content script on
  `<all_urls>`, the `explain-selection` command with `Alt+E`, the toolbar
  action, the options page, and the viewer as a web accessible resource.
- `manifests/firefox.json`: `background.scripts` and
  `browser_specific_settings.gecko.id`.
- `manifests/chrome.json`: `background.service_worker` and a fixed `key`,
  so the extension ID is the same on every machine.
- `build.mjs`: bundle with esbuild and merge the manifests into
  `dist/firefox` and `dist/chrome`.
- `src/content/`: show the "Explain" button next to a selection, extract
  the context, and draw the panel.
  - Context is the text of the closest block ancestor (`p`, `li`, `td`,
    `blockquote`, `pre`, `article`, `section`), one level up if it is
    shorter than about 500 characters, capped at about 3000 characters
    centered on the selection. Also the nearest preceding `h1` to `h3`,
    the page title and the URL.
  - In the PDF viewer the block ancestor is the page's `.textLayer`. Use
    about 1500 characters on each side, the PDF title and the page number.
  - The panel renders markdown with `marked` and `DOMPurify`, follows
    `prefers-color-scheme`, and closes on `Esc`.
- `src/background/`: open one `runtime.connectNative("explain_host")` port
  per conversation and relay messages between the panel and the host. The
  open port keeps the Chrome service worker alive.
  - Watch `webRequest.onHeadersReceived` (non-blocking) for `main_frame`
    responses with `content-type: application/pdf` and redirect the tab
    with `tabs.update` to `viewer.html?file=<url>`. Non-blocking works the
    same in both browsers. The toolbar action covers missed PDFs.
- `src/viewer/`: a viewer page built on `pdfjs-dist/web/pdf_viewer.mjs`
  (`PDFViewer`, `EventBus`, `PDFLinkService`, text layer on). The prebuilt
  PDF.js `viewer.html` rejects `?file=` URLs from other origins. The page
  fetches the bytes itself, passes them to `getDocument({ data })`, loads
  the content script bundle directly, and accepts drag-and-drop and a file
  picker.
- `src/options/`: model alias (`haiku`, `sonnet` default, `opus`), system
  prompt override, PDF redirect toggle, and "Check host", which runs a
  one-word prompt and reports host missing, `claude` missing, not logged
  in, or OK. Firefox treats host permissions as opt-in, so the page also
  shows "Grant access" when `permissions.contains` is false.
- `host/explain-host.mjs`: the native messaging host. Messages are a 4-byte
  native-endian length plus UTF-8 JSON. One port is one conversation and
  one `claude` process. It starts:

  ```
  bwrap <sandbox arguments> -- <claude> -p
    --input-format stream-json
    --output-format stream-json --verbose --include-partial-messages
    --model <alias> --system-prompt <prompt>
    --tools "" --restricted --strict-mcp-config --no-session-persistence
  ```

  It sends `start` and `followup` messages to `claude` on stdin as
  stream-json user messages, sends `delta`, `done` and `error` back to the
  extension, and stops `claude` when the port disconnects.
- `host/sandbox.mjs`: build the bwrap arguments in one function, used by
  the host and by login.
  - `--tmpfs /`, `/nix/store` read-only, and the directory of `claude`
    read-only if it is outside `/nix/store`.
  - The CA bundle read-only, with `SSL_CERT_FILE` and
    `NODE_EXTRA_CA_CERTS`. `--ro-bind-try` for `/etc/resolv.conf`,
    `/etc/hosts`, `/etc/nsswitch.conf`, `/etc/passwd`, `/etc/group` and
    `/etc/localtime`.
  - `--proc /proc`, `--dev /dev`, `--dir /tmp`.
  - `~/.config/explain/home` read-write at `/home/explain`, the only
    writable host path. The working directory is the empty
    `/home/explain/work`.
  - `--unshare-all --share-net --die-with-parent --hostname explain
    --clearenv`, and `--new-session` for the host only. Environment is
    `HOME`, `PATH` (the directory of `claude`), `USER`, `LANG=C.UTF-8` and
    the two CA variables.
  - Write `{"hasCompletedOnboarding":true}` to
    `/home/explain/.claude.json` if it does not exist, as `box` does.
- `host/install.mjs` (`npm run install-host`): resolve `node`, `bwrap`,
  `realpath` of `claude` and the CA bundle into
  `~/.config/explain/host.json`, create `~/.config/explain/home`, write a
  wrapper with the absolute `node` path, and write `explain_host.json` to
  `~/.mozilla/native-messaging-hosts/` (`allowed_extensions`),
  `~/.config/google-chrome/NativeMessagingHosts/` and
  `~/.config/chromium/NativeMessagingHosts/` (`allowed_origins`). The
  browser starts the host with a minimal `PATH`, so every path is absolute.
- `host/login.mjs` (`npm run login`): run `claude /login` in the same
  sandbox, attached to the terminal.
- System prompt: explain the selected text, use the context to resolve
  terms and references, be concise, lead with the explanation. The user
  message wraps the title, URL, page, heading and context in `<document>`,
  then the `<selection>`.
- Later: the host keeps one idle `claude` process ready to remove the
  start time. Selections in iframes need `all_frames: true` and a relay to
  the top frame.

## Verification

1. Before writing the host, run `claude -p` with the flags above by hand
   and confirm which `stream-json` lines carry text deltas and the result,
   and that `--restricted` with `--tools ""` leaves no tools.
2. `npm run install-host` and `npm run login`, then
   `ls ~/.config/explain/home/.claude` shows the login, and no `CLAUDE.md`,
   hooks or MCP servers.
3. A test build of the sandbox with `--tools Bash` cannot list `~/.ssh` of
   the host user, and `claude` there can refresh its login.
4. A framed-JSON test script sends `start` to the host and gets `delta`
   lines and one `done`.
5. "Check host" on the options page reports OK in Firefox and Chrome.
6. On a web page, a local HTML file and an arXiv PDF, selecting a term and
   pressing `Alt+E` streams an answer that uses the surrounding paragraph,
   and a follow-up question gets an answer in the same panel.
7. A local PDF opens in Firefox by drag-and-drop, and in Chrome by
   `file://` with "Allow access to file URLs" on.


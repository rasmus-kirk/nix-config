# Idea: Claude Code network sandbox inside the box

## Context

The box (`modules/home-manager/box`) runs Claude Code under bwrap with either
no network (`--unshare-net`) or the host's full network (`--net`). With
`--net`, every Bash command can reach any host while the tokens in
`~/.secret/tokens-read-only` are exported as env vars.

Claude Code's built-in sandbox adds a domain allowlist for Bash commands and
their children. The box already isolates the filesystem, so the sandbox's
filesystem layer stays on only for one rule: Bash cannot write Claude's own
settings, which would let a command widen its later access.

Scope and limits, from https://code.claude.com/docs/en/sandboxing:

- Covers Bash, PowerShell and Monitor commands and their children.
- Does not cover WebFetch, WebSearch, stdio MCP servers (Notion, Slack),
  hooks or the status line. Remote HTTP MCP (Linear) and Claude's own API
  traffic are not documented either way.
- An unlisted domain is refused in auto mode and prompts in default mode.
  "Yes" allows it for the session. "Yes, and don't ask again" writes a
  `WebFetch(domain:...)` rule to local settings, to move into Nix later.
- `strictAllowlist` stays off so the prompt path above works. Bypass mode
  is disabled instead, because bypass ignores a non-strict allowlist.

Enable it only in the sandbox home configs. Host Claude sessions keep their
current settings.

## Changes

- `modules/home-manager/claudeConfig/default.nix`: add
  `kirk.claudeConfig.sandbox.enable` and
  `kirk.claudeConfig.sandbox.allowedDomains` (list of str). When enabled,
  merge into `settings`:

  ```nix
  sandbox = {
    enabled = true;
    failIfUnavailable = true;
    allowUnsandboxedCommands = false;
    enableWeakerNestedSandbox = true;
    network.allowedDomains = cfg.sandbox.allowedDomains;
    filesystem = {
      allowWrite = ["/data"];
      denyWrite = ["~/.claude" "/data/**/.claude"];
    };
  };
  permissions.disableBypassPermissionsMode = "disable";
  ```

  and add `pkgs.bubblewrap` and `pkgs.socat` to `home.packages`.
  `~/.claude/settings.json` is already a read-only Nix store link. The
  `denyWrite` covers `settings.local.json`, hooks and project `.claude/`
  directories. Check the glob syntax `sandbox.filesystem` accepts, and adjust
  the project pattern to match.
- `configurations/home-manager/sandbox/home.nix`: enable it with the core
  allowlist:

  ```nix
  claudeConfig.sandbox = {
    enable = true;
    allowedDomains = [
      "cache.nixos.org"
      "channels.nixos.org"
      "tarballs.nixos.org"
      "github.com"
      "api.github.com"
      "codeload.github.com"
      "*.githubusercontent.com"
      "crates.io"
      "index.crates.io"
      "static.crates.io"
      "static.rust-lang.org"
      "test-qms.com"
      "*.test-qms.com"
    ];
  };
  ```

  Add more only when a repo needs them. Go uses `proxy.golang.org` and
  `sum.golang.org`. TypeScript uses `registry.npmjs.org`. Python uses
  `pypi.org` and `files.pythonhosted.org`. Containers use `ghcr.io` and
  `pkg-containers.githubusercontent.com`.

## Verification

Run these in a box started with `--net`. Steps 1 to 5 can run before the Nix
change, with the settings above written to a JSON file and passed as
`claude --settings <file>`.

1. Claude starts. With `failIfUnavailable`, a nested bwrap failure exits
   at startup. If it fails, check whether the box blocks nested user
   namespaces. The box passes no `--disable-userns`, and the hardening
   module sets no userns sysctl.
2. In auto mode, `curl -sI https://github.com` succeeds and
   `curl -sI https://example.com` is refused.
3. In default mode, the `example.com` curl prompts.
4. `touch ~/.claude/settings.local.json` and
   `touch /data/.system-configuration/.claude/x` fail, and
   `touch /data/.system-configuration/.scratchpad/x` succeeds.
5. `claude --dangerously-skip-permissions` refuses to start.
6. `cargo fetch` in a lighthouse checkout succeeds. If it fails, add the
   domain it names.
7. Check whether `test-qms.com` is needed next to `*.test-qms.com`, and
   whether the Linear MCP and Claude's API traffic still work. Both are
   expected to sit outside the sandbox.

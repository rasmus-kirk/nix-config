---
name: manual
description: Work in manual mode. The session runs unsandboxed and the user approves every command by hand. Use when the user invokes /manual or says the session is unsandboxed or manual.
---

# Manual Mode

Every command runs unsandboxed on the host, after the user reads and approves it.

Auto mode approves commands without the user, so it breaks manual mode. Before the first command, check your context for auto mode. If auto mode is active, stop and tell the user to switch it off with Shift+Tab. Check again before each command if your context shows that the permission mode changed.

**Above all else, each command must be readable.** The user must understand a command after one read. Readability wins over every other rule, including approving fewer commands.

- Read files with Read, never Bash. Use Bash for other reads, for example searches and `git log`.
- Never use awk.
- Avoid using sed whenever possible.
- Use absolute paths. Never hide work in `$(...)`, backticks, `eval`, `xargs`, `sh -c` or encoded strings. Pipe only into read-only stages.
- Run one command per Bash call. Never chain commands with `;`, `&&` or `||`.
- Use `sudo` without `-n`, because `-n` blocks the YubiKey touch prompt. Never pipe a `sudo` command.
- Write only inside the working directory or your scratchpad. Never edit dotfiles, `~/.ssh`, `~/.gnupg` or keyrings. Never read secrets or `.env` files.
- Before a delete or overwrite, show what it removes.
- Before several commands, list them one per line.
- Three or more commands that change state go through the user-script skill.

## Preferred Tools

Prefer these tools for these tasks.

- Find files: `fd`, not `find`
- Search file contents: `rg`, not `grep`
- Delete files: `trash-put`, not `rm`
- Read JSON: `jq`, not `grep` or `sed`
- Show directory sizes: `dust`, not `du`
- Show free disk space: `duf`, not `df`

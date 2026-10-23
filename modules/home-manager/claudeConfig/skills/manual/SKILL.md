---
name: manual
description: Work in manual mode. The session runs unsandboxed and the user approves every command by hand. Use when the user invokes /manual or says the session is unsandboxed or manual.
---

# Manual Mode

Every command runs unsandboxed on the host, after the user reads and approves it.

**Above all else, each command must be readable.** The user must understand a command after one read. Readability wins over every other rule, including approving fewer commands.

- Read with Read, Grep and Glob, never Bash. Use Bash for reads only when no tool covers it, for example `git log`.
- Never use awk.
- Use absolute paths. Never hide work in `$(...)`, backticks, `eval`, `xargs`, `sh -c` or encoded strings. Pipe only into read-only stages.
- Chain only read-only commands. A command that changes state runs alone.
- Use `sudo` without `-n`, because `-n` blocks the YubiKey touch prompt. A `sudo` command always runs alone, never chained or piped.
- Write only inside the working directory or your scratchpad. Never edit dotfiles, `~/.ssh`, `~/.gnupg` or keyrings. Never read secrets or `.env` files.
- Before a delete or overwrite, show what it removes.
- Before several commands, list them one per line.
- Three or more commands that change state go through the user-script skill.

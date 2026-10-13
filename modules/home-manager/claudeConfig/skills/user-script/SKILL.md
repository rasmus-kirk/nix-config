---
name: user-script
description: Write a step-by-step script for the user to run when they must run more than two commands for you, for example because of sudo, permissions, the sandbox, or another host. Use it automatically whenever you would otherwise list three or more commands for the user.
---

# User Script

The user reads the script once, top to bottom, then runs it and pastes the full output back to you. Write for that reader.

For one or two commands, ask the user to run them with `! <command>` instead.

## Steps

1. Write the template below to the project's `.scratchpad/<task>.sh`. Create `.scratchpad/` if it is missing.
2. Keep the `step`, `run` and `pause` helpers exactly as written. Replace the example steps.
3. Run `chmod +x` and `shellcheck` on the script.
4. Give the user the path, one line per step, and every command that cannot be undone.
5. Read the pasted output after each `pause`. Tell the user whether to continue.

## Rules

- Every command goes through `run`, including reads. Only `step`, `pause` and `echo` stand alone.
- Commands never hide inside `$(...)` or pipes, because `run` shows only the command it receives.
- Use `sudo` only when the command needs root.
- The script prints raw state, for example `ls -la`, `cat` or `stat`. You verify the output. The script holds no tests, asserts or expected values.
- Put `pause "Paste the output above to Claude."` wherever you must see output before the next command runs. Always put one before an irreversible command.
- Before a command that deletes, run a command that shows what it deletes.
- Write straight-line code. No helpers beyond the template, no if/else, no re-run logic, no dry run, no preflight.
- Each `step` header is numbered `N/M` and says what the step changes and why.
- Order the steps so that a failure at any point leaves a working system.
- Use variables only for paths that repeat.

## Template

```sh
#!/usr/bin/env bash
set -euo pipefail

step() {
  echo
  printf '\033[1m==> %s\033[0m\n' "$1"
}

run() {
  local cmd answer
  printf -v cmd '%q ' "$@"
  echo
  printf '\033[1m>\033[0m \033[37m$ %s\033[0m\n' "${cmd% }"
  read -r -s -n1 -p $'\033[1m[Press Enter to run]\033[0m ' answer
  echo
  echo
  if [ -n "$answer" ]; then
    echo "Aborted."
    exit 1
  fi
  "$@"
}

pause() {
  local answer
  echo
  echo "$1"
  read -r -s -n1 -p $'\033[1m[Press Enter to continue]\033[0m ' answer
  echo
  if [ -n "$answer" ]; then
    echo "Aborted."
    exit 1
  fi
}

step "1/3  <What this step changes and why>"
run <command>

step "2/3  Verify"
run <command that prints the new state>
pause "Paste the output above to Claude."

step "3/3  <What this step changes and why>"
run <command that prints what the next command removes>
run <command>

echo
echo "Done."
```

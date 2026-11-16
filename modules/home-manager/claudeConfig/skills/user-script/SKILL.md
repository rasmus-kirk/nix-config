---
name: user-script
description: Write a step-by-step script for the user to run when they must run more than two commands for you, for example because of sudo, permissions, the sandbox, or another host. Use it automatically whenever you would otherwise list three or more commands for the user.
---

# User Script

The user runs the script with `user-script` and reviews each command at its prompt. The user does not read the file first. Write each command so that the user understands it at its prompt.

For one or two commands, ask the user to run them with `! <command>` instead.

## Format

`user-script` runs a file of these lines:

- `# <text>` starts a step. The runner numbers the steps.
- `$ <command>` is one bash command line. The runner shows it with the current directory and runs it after the user presses Enter. All lines run in one bash process, so `cd`, variables and functions carry over.
- `?` pauses and tells the user to ask you to read the log. `? <text>` pauses with your own text.
- Blank lines are allowed.

The runner rejects the whole file before it runs anything if a line has another form or holds a control character other than tab. It stops at the first command that exits non-zero. It writes everything it prints to `<file>.log`.

## Steps

1. Write the file to the project's `.scratchpad/<task>`, with no extension and no exec bit. Create `.scratchpad/` if it is missing.
2. Give the user the start command with the absolute path of the file, `user-script /path/to/project/.scratchpad/<task>`.
3. Give the user one line per step and every command that cannot be undone.
4. When the user reaches a `?`, read `.scratchpad/<task>.log`. Tell the user whether to continue.

## Rules

- The script starts in the directory where the user runs `user-script`. If a command uses a relative path, make `$ cd <absolute path>` the first command.
- Write each command on one line. Heredocs and `\` continuations do not work.
- Use `sudo` only when the command needs root.
- The script prints raw state, for example `ls -la`, `cat` or `stat`. You verify the output in the log. The script holds no tests, asserts or expected values.
- Put a `?` wherever you must see output before the next command runs. Always put one before an irreversible command.
- Before a command that deletes, run a command that shows what it deletes.
- Write straight-line commands. No functions, if/else, re-run logic, dry run or preflight.
- Each step text says what the step changes and why.
- Order the steps so that a failure at any point leaves a working system.

## Example

```
# Install the udev rule so the YubiKey works without root
$ cd /data/.system-configuration
$ sudo cp .scratchpad/70-yubikey.rules /etc/udev/rules.d/
$ ls -la /etc/udev/rules.d/
?

# Reload udev so the rule applies without a reboot
$ sudo udevadm control --reload-rules
$ sudo udevadm trigger
```

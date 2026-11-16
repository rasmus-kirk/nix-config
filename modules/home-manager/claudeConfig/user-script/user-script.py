import os
import shlex
import subprocess
import sys
import unicodedata
from pathlib import Path

import typer

BASH = os.environ["USER_SCRIPT_BASH"]
SCRIPT = os.environ["USER_SCRIPT_SCRIPT"]
LOGGING = "USER_SCRIPT_LOGGING"


class Shell:
    def __init__(self):
        commands_read, commands_write = os.pipe()
        status_read, self.status_fd = os.pipe()
        subprocess.Popen(
            [BASH, "--norc", "--noprofile", f"/dev/fd/{commands_read}"],
            pass_fds=[commands_read, self.status_fd],
        )
        os.close(commands_read)
        os.close(self.status_fd)
        self.commands = os.fdopen(commands_write, "w")
        self.status = os.fdopen(status_read)
        self.cwd = os.getcwd()

    def run(self, line):
        report = f"printf '%s %s\\n' \"$?\" \"$PWD\" >&{self.status_fd}"
        self.commands.write(f"eval {shlex.quote(line)}\n{report}\n")
        self.commands.flush()
        status = self.status.readline()
        if not status:
            stop("Bash exited. Stopped.")
        exit_code, self.cwd = status.rstrip("\n").split(" ", 1)
        return int(exit_code)


app = typer.Typer(add_completion=False, pretty_exceptions_enable=False)


def stop(message):
    typer.echo(message, err=True)
    raise typer.Exit(1)


def bold(text):
    return typer.style(text, bold=True)


def wait_for_enter(prompt):
    answer = typer.prompt(
        bold(f"[{prompt}]"),
        default="",
        show_default=False,
        prompt_suffix=" ",
    )
    if answer:
        stop("Aborted.")


def is_hidden(char):
    return char != "\t" and unicodedata.category(char) in ("Cc", "Cf")


def read_lines(path):
    with open(path, newline="") as file:
        lines = file.read().split("\n")
    for number, line in enumerate(lines, 1):
        if any(is_hidden(char) for char in line):
            stop(f"Line {number} holds a control character.")
        if line.strip() and not line.startswith(("# ", "$ ", "?")):
            stop(f"Line {number} is not a step, command or pause.")
    return lines


def run_lines(lines):
    steps = len([line for line in lines if line.startswith("# ")])
    step = 0
    shell = Shell()
    for line in lines:
        if line.startswith("# "):
            step += 1
            typer.echo("\n" + bold(f"==> {step}/{steps}  {line[2:]}"))
        elif line.startswith("$ "):
            command = line[2:]
            typer.echo(f"\n{bold(f'{shell.cwd} $')} {command}")
            wait_for_enter("Press Enter to run")
            exit_code = shell.run(command)
            if exit_code != 0:
                stop(f"Exit code {exit_code}. Stopped.")
        elif line.startswith("?"):
            text = line[1:].strip() or "Tell Claude to read the log."
            typer.echo(f"\n{text}")
            wait_for_enter("Press Enter to continue")
    typer.echo("\nDone.")


@app.command()
def main(
    path: Path = typer.Argument(metavar="FILE", exists=True, dir_okay=False),
):
    lines = read_lines(path)
    if os.environ.get(LOGGING):
        run_lines(lines)
        return
    os.environ[LOGGING] = "1"
    command = shlex.join([sys.executable, sys.argv[0], str(path)])
    os.execv(SCRIPT, [SCRIPT, "-qefc", command, f"{path}.log"])


app(prog_name="user-script")

---
name: ask
description: Answer the question and nothing else. No commands, no writes, no CI.
---

This turn is a question, not a task.

Prefer:
- A direct answer from knowledge
- Three sentences over ten
- Producing the answer first, not reasoning at length before it

Reading is allowed but a direct respond is always preferred:
- Read only when the answer depends on something in this repository
- Read the specific file, not its neighbours
- Use the Read, Grep, and Glob tools
- Never sweep, never grep for background, never open a file to be thorough

Never:
- Run a command. Not builds, tests, CI, git, ls, cat, or a version check. Zero.
- Use a shell for reads
- Write anything. No files, no edits, no scratch files, no memory, no config.
- Spawn agents, workflows, or background tasks

If the answer needs forbidden work:
- Say so in one line and stop
- Naming what you would need to run is correct
- Independently deciding to perform the work is never correct

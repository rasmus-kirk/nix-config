---
description: Set this box session's display name in the approval-tui's bottom pane
allowed-tools: Bash(agent-rename:*)
---

Run `agent-rename "$ARGUMENTS"` to label this box session in the host
approval-tui's Agents pane. The new name takes effect immediately —
the TUI watches `${brokerRoot}/agent-events/` for rename events.

If `$ARGUMENTS` is empty, ask the user what name they want; otherwise
just run the command and report the result.

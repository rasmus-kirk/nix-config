---
name: whip
description: Find the mistake in your previous response, fix it, and log it in `~/.claude/whip-log.md`. Use when the user says "whip", or says that you did something stupid, wrong or careless.
---

# Whip

The user thinks your previous response contains a mistake. A mistake is a wrong
action, a wrong assumption, a broken instruction or wasted work. If the user
names a different response or a specific mistake, use that instead.

1. Find the mistake. Re-read the previous response, the user message before
   it, and the instructions that applied to it. Check each claim and each
   action against the code, the command output and the instructions. If more
   than one candidate fits and the user did not name one, list them and ask.
2. Fix it. Revert changes the user did not order. Redo the work the way it
   should have been done. Confirm first if the fix is destructive or
   outward-facing.
3. Log it. Append one entry to `~/.claude/whip-log.md`. Create the file if it
   does not exist. Reuse a category from the log if one fits. Otherwise add a
   new one.
4. Check for repeats. If the log has an earlier entry in the same category,
   propose a rule that prevents the mistake. Write it as an edit to the source
   in this repo at `modules/home-manager/claudeConfig/`, for example
   `CLAUDE.md` or `style-rules.md`, because Home Manager links
   `~/.claude/CLAUDE.md` read-only from the Nix store. If the mistake broke a
   rule that already exists, the rule failed. Propose a sharper rule or a hook
   instead of a second copy. Do not apply the edit.

Answer with the mistake in one sentence, the fix, and the proposed rule if
there is one. Do not apologize.

## Log entry

Get the date from `date +%F` and the repo from
`basename "$(git rev-parse --show-toplevel)"`.

```markdown
## 2026-11-09 nix-config: ignored instruction

- Did: Wrote the skill before the user ordered it.
- Should have: Proposed the design and waited for an order.
- Broke: "Only make changes when you are explicitly ordered to do so."
```

Write `none` after `Broke:` if no instruction covers the mistake.

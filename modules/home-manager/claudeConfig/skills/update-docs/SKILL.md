---
name: update-docs
description: Use when a PR is written and a review is requested. Reports what the change leaves out of sync in Linear, Notion, GitHub, and other repos, including documentation. Read-only. The user does the updating.
---

This turn is a cross-check of a change against the places a code review misses. Find what is out of sync and report it. Only read. Do not write, edit, or delete any file, issue, page, or comment.

Start from the diff. Use `git diff` against the base branch, or `gh pr diff` when a PR exists. Note the behavior, names, commands, options, and interfaces that changed.

Check these places:

1. Linear. Find the issue the PR belongs to. Check that the diff meets its description and acceptance criteria. Check that its status fits the work. Find other issues this change closes, blocks, or makes stale.
2. Notion. Find pages that describe the changed behavior. Check that they match the new code.
3. Other repos. Use `gh search code` and `gh search issues` to find repos in the same owner or organization that mention the changed names, commands, or interfaces. Check their documentation and their callers.
4. This repo. Check `README.md`, the docs directory, doc comments, and design notes. A design note whose work is done is ready to delete. One whose plan changed is stale.

Report:

- One item per gap. Give the place, what is wrong or missing, and the part of the diff that caused it.
- Group by place.
- Put gaps that mislead first and missing documentation after.
- Say "nothing to update" when that is the result.
- Link each item to the page, issue, or file.

If a source is unreachable, name it and say what went unchecked.

Verify each gap against the code before reporting it. Draft replacement text only when asked.

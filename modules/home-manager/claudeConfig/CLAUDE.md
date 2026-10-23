*x* should be designed not by piling feature on top of feature, but by removing
the weaknesses and restrictions that make additional features appear necessary.

## Scratchpad

- Put temporary scripts, documents, and worktrees meant for the user or other agents in `.scratchpad/`. Anything only you interact with stays in your own scratchpad.

## Box

`box` is a bubblewrap sandbox. Inside it, `$BOX` is `1`. A session can move between host and box. When a task needs the other side, give the user these steps, with your session ID filled in.

1. Exit Claude.
2. On the host, run `box copy in <id>` to go into the box, or `box copy out <id>` to go out.
3. On the other side, run `claude --resume <id>`.

## Reading CI Status

`gh pr checks` and `statusCheckRollup` fail with "Resource not accessible by personal access token", because the fine-grained `GH_TOKEN` can't read the Checks API. Use the Actions API instead:

- `gh run list --branch <branch>` shows the workflow runs for a PR branch.
- `gh api "repos/qmsfinance/lighthouse/actions/runs?head_sha=$(gh pr view <n> --json headRefOid -q .headRefOid)"` shows the runs for the PR's head commit.
- `gh run view <run-id> --json jobs --jq '.jobs[]|"\(.name): \(.conclusion)"'` shows the result of each job.

## Git

Commits are signed with the user's YubiKey, so only the user commits.

- Never commit or push.
- Prepare merges and picks up to the commit:
  - Merges: `git merge --no-commit --no-ff`, resolve the conflicts, stage the result.
  - Picks: `git cherry-pick --no-commit`.
- For a merge, give the user `git show --remerge-diff HEAD` to review the resolution after the commit.
- Never write anything on GitHub, including comments, reviews, PRs, etc.

## Publishing

- Never try to post anywhere on behalf of the user (GitHub, Linear, Notion, Slack). Consider yourself read-only on these domains.
- You may draft messages/posts for the user, just not post them.

## Suggestions

When a decision needs the user's input, label each option with a response number plus a letter:

12a. Do x. (recommended)
12b. Do y.

- Only responses with options get a number. Numbers start at 1 per session and go up by one for each response with options, so labels never repeat.
- Put the recommended option first and mark it.
- A plain letter (`a`) refers to the options in the latest response.
- Responding with an option that names an action is an order to do it.
- A label with a question mark (`7a?`) is an order to explain that option, not to do it.
- No catch-all option like "something else?". The user can always answer freely.
- Cite an earlier option like a reference. The sentence must read correctly with the brackets removed. Looking up a bare label means scrolling back through the conversation, which is frustrating:
  - "We kept `CONFIG_NAME` [4b]."
  - "Rerunning the network split [1d] is still open."
- Bring up an open option again only when it blocks the next step, or when the user asks for a status or overview.

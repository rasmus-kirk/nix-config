*x* should be designed not by piling feature on top of feature, but by removing
the weaknesses and restrictions that make additional features appear necessary.

## Reading CI Status

`gh pr checks` and `statusCheckRollup` fail with "Resource not accessible by personal access token", because the fine-grained `GH_TOKEN` can't read the Checks API. Use the Actions API instead:

- `gh run list --branch <branch>` shows the workflow runs for a PR branch.
- `gh api "repos/qmsfinance/lighthouse/actions/runs?head_sha=$(gh pr view <n> --json headRefOid -q .headRefOid)"` shows the runs for the PR's head commit.
- `gh run view <run-id> --json jobs --jq '.jobs[]|"\(.name): \(.conclusion)"'` shows the result of each job.

## Git

Never:

- Commit.
- Push
- Write anything on GitHub, including comments, reviews, PR's, etc.

## Publishing

- Never try to post anywhere on behalf of the user (GitHub, Linear, Notion, Slack). Consider yourself read-only on these domain.
- You may draft messages/posts for the user, just not post them.

## Suggestions

When a decision needs my input, label each option with a response number plus a letter:

12a. Do x. (recommended)
12b. Do y.

- Only responses with options get a number. Numbers start at 1 per session and go up by one for each response with options, so labels never repeat.
- Put the recommended option first and mark it.
- A plain letter (`a`) refers to the options in the latest response.
- Responding with an option that names an action is an order to do it.
- A label with a question mark (`7a?`) is an order to explain that option, not to do it.
- No catch-all option like "something else?". I can always answer freely.
- Cite an earlier option like a reference. The sentence must read correctly with the brackets removed. Looking up a bare label means scrolling back through the conversation, which is frustrating:
  - "We kept `CONFIG_NAME` [4b]."
  - "Rerunning the network split [1d] is still open."
- Bring up an open option again only when it blocks the next step, or when I ask for a status or overview.

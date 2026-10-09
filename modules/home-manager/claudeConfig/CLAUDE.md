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

If you need input from the user to take a decision and you suggest a solution, it should be UNIQUELY labeled with a single symbol/number:

a. Do x?
b. Do y?
c. Something else?

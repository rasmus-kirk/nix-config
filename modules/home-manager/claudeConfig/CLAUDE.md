*x* should be designed not by piling feature on top of feature, but by removing
the weaknesses and restrictions that make additional features appear necessary.

## Reading CI status

`gh pr checks` and `statusCheckRollup` fail with "Resource not accessible by personal access token", because the fine-grained `GH_TOKEN` can't read the Checks API. Use the Actions API instead:

- `gh run list --branch <branch>` shows the workflow runs for a PR branch.
- `gh api "repos/qmsfinance/lighthouse/actions/runs?head_sha=$(gh pr view <n> --json headRefOid -q .headRefOid)"` shows the runs for the PR's head commit.
- `gh run view <run-id> --json jobs --jq '.jobs[]|"\(.name): \(.conclusion)"'` shows the result of each job.

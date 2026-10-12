---
name: review-pr
description: Review a PR with code-review and update-docs, then walk through the findings one at a time with the user, recording each decision in a file. Use whenever the user asks to review a PR, a branch, or a diff. Preferred over code-review.
---

# Review PR

1. Run the `code-review` skill on the PR without `--comment`.
2. Run the `update-docs` skill on the same PR.
3. Check other worktrees and branches for related work.
3. Verify each finding in the code. Write the findings of both skills to a review file somewhere visible to the user, most important first, using the template below.
4. Present one finding per message. Describe the finding in full before giving options and a recommendation. State what was verified and what was assumed.
5. Wait for the user's decision. "Next" and "ignore" are decisions. Questions are not orders to change code.
6. Record the decision in that finding's subsection, in the user's words.
7. At the end, give a table of findings and decisions.

## Template

```markdown
# Review of <PR>

Not run or not verified: <list>

## Findings

### 1. <title>

File: `<path>:<line>`

<description and failure scenario>

#### How it is addressed

> Unaddressed
```

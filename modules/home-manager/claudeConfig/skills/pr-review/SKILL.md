---
name: pr-review
description: Review a PR with code-review and pr-docs, then walk through the findings one at a time with the user, recording each decision in a file. Use whenever the user asks to review a PR, a branch, or a diff. Preferred over code-review.
---

# Review PR

1. Run the `code-review` skill on the PR without `--comment`.
2. Run the `pr-docs` skill on the same PR.
3. Check other worktrees and branches for related work.
4. Verify each finding in the code.
5. Send one message that lists every verified finding, numbered, one line each, most significant first. Each line names the problem and its consequence. Wait for the user to drop findings.
6. Write the kept findings to a review file somewhere visible to the user, most important first, using the template below.
7. Present one kept finding per message. Describe the finding in full before giving options and a recommendation. State what was verified and what was assumed.
8. Wait for the user's decision. Questions are not orders to change code.
9. Record the decision in that finding's subsection, in the user's words.
10. At the end, give a table of findings and decisions.

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

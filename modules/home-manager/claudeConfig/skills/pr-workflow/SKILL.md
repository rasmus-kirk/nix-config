---
name: pr-workflow
description: The procedure for taking a change from idea to one or several reviewed PRs. Use when the user starts work meant to become one or several PRs.
---

# PR Workflow

Move to the next step only when the user says so.

Steps 1 to 3 may span several PRs, each with one concern:

1. **Design:** Ask the user for the requirements and the decisions that
   already exist. Then agree on a plan and split it into PRs, in merge order.
2. **Draft:** Implement the plan. Run the build, lints and relevant tests.
3. **Discuss:** Revise the diff until the user calls it ready.

Steps 4 to 7 run once per PR:

4. **Document:** Run the `pr-comments` skill.
5. **Understand:** Offer the `quiz` skill.
6. **Describe:** Run the `pr-description` skill. The user opens the PR.
7. **Review:** The user runs the `pr-review` skill in a fresh session. The
   session that wrote the code never reviews it.

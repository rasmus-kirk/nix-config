---
name: pr-description
description: Draft a PR title and description in the user's style. Use whenever the user asks for a PR description, PR text, or a PR title, or is about to open a PR.
---

# PR Description

Draft only. The user posts the PR.

Load the writing-style skill before you draft.

## Steps

1. Read:
   - The diff against the base branch
   - The commit log
   - The repository's PR template
   - The titles and descriptions of the user's last 5 PRs (`gh pr list --author @me --state all --limit 5 --json title,body`)
2. If the PR resolves a Linear issue, read it and prefix the title with its key.
3. Draft right away. Infer the motivation from the diff, the commits, the issue, and this conversation. Under Testing, list only the tests the diff adds or changes, and manual runs of the software in this conversation. Never state that tests, lints, or CI pass. CI reports that.
4. Give the draft in a ````text block, then revise it from the user's corrections:

   ````text
   Title: <title>
   Commit Message: <commit message>
   Body:

   ```md
   <body>
   ```
   ````

## Title

`[<LINEAR-KEY>: ][<Category> - ]<Summary>`

- `<Category>` groups the PR with related PRs. It names a module, a feature, or a series, for example `Miner`, `Local Devnet`, `Difficulty Adjustment` or `Cleanup`. Reuse a category from the user's recent PR titles when one fits. Leave the category out when none fits.
- `<Summary>` starts with a verb, in Chicago title case. Code identifiers go in backticks.
- Examples:
  - ``CORE-217: Difficulty Adjustment - Move `Target` to `types::pouw` ``
  - ``Miner - Check for a New Prepared Block before Each Mining Step``
  - ``Cleanup - Remove the Trivial Target``

## Body

Follow the repository's PR template and the style of the user's last 5 PRs.

- Motivation (if present): at most 4 short sentences. Problem first, then what the PR does about it. No implementation detail, that goes in Changes.
- Changes (if present): one sentence per bullet, at most 25 words. Add a second sentence only for a consequence a reviewer must know.
- Call out breaking changes with "This is a breaking change" and say who it breaks.
- Leave all checklist boxes unchecked. The user ticks them.
- Add no attribution footer.
- Before you send the draft, cut every sentence that a reviewer of the diff does not need.

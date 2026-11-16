---
name: eli5
description: Explain a question, a topic or a pasted text in plain words, for example how a part of the code works, a step of a proof, an agent's response, a PR comment or a design note. Use when the user asks how something works in simple terms, pastes a text they do not understand, or asks for an ELI5 or a simple explanation.
---

# ELI5

Explain something so that a reader who knows the project but not this topic
understands it on the first read.

Load the writing-style skill and follow it. Load it again even if it is
already in your context.

The material is what the session works on and what the explanation rests on,
for example code, a document, a paper or a derivation.

## Input

The user gives one of these:

- **A question or a topic:** for example `/eli5 how gossip scoring works`.
  Answer the question from the material.
- **A paste:** Explain the paste.
- **Nothing:** Explain your previous answer.

The input is something that the user did not understand and will not read
again. Write the explanation so that it stands alone.

- State the content as plain statements, for example "The warm-up has no
  effect", not "The answer argues that the warm-up has no effect".
- Never refer to the input, quote it or point to a part of it.
- Never use a term, name or number from the input without defining it.

## Scope

- Add no new proposal, fix or recommendation.
- Read the material that the explanation needs, so that you can cite it and
  define its terms. Run no commands that change anything.
- Verify each claim against the material. For a math step, derive the step
  yourself.
- Mark each claim that you did not verify with a tag, as the writing-style
  skill describes.

For a paste or your previous answer, also follow these rules:

- Keep the claims, the argument and the conclusion of the input.
- Do not act on options in the input. Keep their labels, for example `6a`,
  so the user can answer the original session.
- If the material contradicts a claim, state what the material shows in the
  Summary and cite it. Name each option of the input that the contradiction
  affects.

## Steps

1. Identify the input.
2. Find the question to answer. For a paste or your previous answer, find the
   question that the input answers.
3. List each term, acronym and name that the explanation needs. Find out what
   each one means in the material.
4. Find the answer in the material. For a paste or your previous answer, check
   the claims of the input.
5. Order the content from what the reader knows to what is new, in the format
   below.
6. Write the explanation in your response, not in a file.

## Format

Use these sections in this order. Leave out a section that has no content.

### `## Summary`

One or two short paragraphs. The first sentence answers the question. Then
state what is currently true and, for an input that proposes a change, what
changes.
If the material contradicts a claim of the input, end with what the material
shows.

### `## Background`

What the reader needs to know for the rest of the explanation, for example
how the system currently works or which definitions a proof uses.

- Describe a process as numbered steps, in the order it happens.
- Define each term on first use. For a group of terms, use a list with the
  term in bold, followed by its definition.

### One section per step of the explanation

Give each section a header that states its topic, for example `## Why the
warm-up has no effect`.

- Show where each number comes from. Give the formula and its values, for
  example "0.685² × 0.5 × 0.5 ≈ 0.12".
- Use a table only to compare several options or places over the same
  columns.
- Use a code block for a type, a signature or a formula that the reader must
  read exactly.

### `## What changes`

Only for an input that proposes a change. What the input proposes to delete, add
or change, as a list. End with the options of the input, with their original
labels. Restate each option in plain words.

### `## References`

Every reference of the explanation, in the order of first use. See
"Citations".

## Citations

- Cite with footnotes. Put `[n]` after the sentence. This applies to every
  reference, for example a place in the material, a PR, an issue, a spec or
  a thread.
- List all footnotes in the `## References` section at the very end. Put no
  footnote list in any other section.
- Number the footnotes in one sequence across the whole explanation.
- Point to the exact place, for example a line of code, a section of a
  document, an equation or a page of a paper.

  ```
  ## References

  - \[1\] See `path/to/file.rs:230` (`function_name`)
  - \[2\] See `docs/design.md`, section "Signing root"
  - \[3\] See <authors>, "<paper title>", equation <n>
  ```

- Cite only places that you read.
- Keep names from the material, for example function names or equation
  numbers, out of the prose unless the reader needs the name to find the
  place. Put the name in the footnote.

## Rules

- Write paragraphs and lists, not fragments. Each paragraph has one topic.
- Use real headers. Do not use bold text as a header.
- Use no analogies to everyday objects. Explain the real mechanism in plain
  words.
- Keep the length that the content needs. A short question can get a short
  explanation with only a summary and one section.

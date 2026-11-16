---
name: writing-style
description: Rules for writing documentation. Use when you write or edit documentation, for example a README, a design document, a proposal, or a PR description.
---

# Writing Style

This skill adds to the rules in `~/.claude/style-rules.md`. Always read that
file, even if it is already in your context.

Always load the botbabble skill, even if it is already in your context. Use
its definition and examples, not its rewrite steps. Before you send a text,
compare it with the examples and rewrite each passage that matches one.

Use the Google developer documentation style guide as the fallback. This
skill and `style-rules.md` take precedence over it.

## Content

- Write only what was observed or verified. Mark everything else, that is
  guesses, unverified claims and open questions, with a numbered tag, for
  example `[C1]`. List the tags under **Confirm before publishing** at the
  end of the subsection.
- Cut every fact that does not support the point of its paragraph, however
  true or interesting it is.
- Write a fact because the reader needs it, never because you know it.

## Terms

- Don't invent new terms. Use only terms that the project or the field
  already uses. Describe everything else in plain words.
- Name a part of the code only if the reader needs the name to find it.
  Otherwise describe what the part does.

## Layout

- Never stack headings. Give each section with subsections a lead-in.
- Never start a sentence with inline code or a math symbol.
- Pad each table cell with spaces so that the columns align in the source.
  Make the separator row as wide as each column.

  ```
  | Name   | Description         |
  | ------ | ------------------- |
  | First  | A short value       |
  | Second | A much longer value |
  ```

- Always aim for tables under 90 characters wide. Exceed this only for a
  comparison over many columns.

## ASD-STE100

These rules come from ASD-STE100. Each rule ends with an STE100 citation.

### Words

- Choose short, plain names. No jargon or slang as names. (STE100 1.9, 1.10)
- Use at most three words in a multi-word noun. Break longer ones up with
  "of", "on" or "for". (STE100 2.1)
- Write "for example", "that is" and "and so on", not "e.g.", "i.e." and
  "etc.". (STE100 GR-6)
- Write "currently", not "today", for the present state of a system. Use
  "today" only for the calendar date.

### Sentences

- Write complete sentences. Do not drop articles or other words. (STE100 4.2)
- Use at most 20 words in an instruction and 25 in a description.
  (STE100 5.1, 6.3)
- Write one instruction per sentence, in the imperative. (STE100 5.2, 5.3)
- Put a condition first, then the instruction. "If the build fails, read the
  log." (STE100 5.4)
- Replace a pronoun with its noun if it can refer to more than one thing.
  This applies to "this" in particular. (STE100 GR-3, GR-4)

### Structure

- Give information in steps, from what the reader knows to what is new.
  (STE100 6.1)
- Give each paragraph one topic, and state it in the first sentence.
  (STE100 6.5)
- Use at most six sentences in a paragraph. (STE100 6.6)
- A note gives information. Put instructions in the steps, not in notes.
  (STE100 5.5)
- Before a step that can cause damage or data loss, write a warning. State
  the risk and the result. (STE100 7.1, 7.2, 7.3)

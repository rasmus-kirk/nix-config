---
name: quiz
description: Quiz the user on a diff with quick multiple-choice questions to check their understanding. Use when the user asks for a quiz or to check their understanding of a change, and offer it when the user calls a change ready, before a PR description.
---

# Quiz

A quick self-check. A user who fully understands the diff breezes through it and aces it. A miss shows a gap.

## Steps

1. Read the diff and its callers. Write 4, 8 or 12 questions, more for a larger diff. Weight them toward the parts the user has not discussed or looked at in this conversation.
2. Ask 4 questions per `AskUserQuestion` call. This skill overrides the default that reserves the tool for decisions.
3. After each call, confirm the right answers in one line. For each miss, "Other" or unsure answer, explain the gap briefly with the code.
4. At the end, give the score and list the questions missed.

## Questions

Make questions hard. Answering needs real understanding of the change, not a skim of the diff. A user who understands the change still answers each one in seconds.

Ask about behaviour and reasons, never about names or line numbers:

- Predict: "What does `f` return when the cache is empty?"
- Reason: "Why does the check run before the mining step, not after?"
- Break: "What fails if you remove this line?"
- Change: "Where would you change the code to support a second builder?"

Make each wrong option a mistake a reader could actually make, for example:

- The behaviour before the change
- The right steps in the wrong order
- An off-by-one or a wrong boundary
- An effect that happens, but in a different part of the code

Format:

- The question text starts with `Quiz N/M:` and points to the code with `path:line`.
- Always prefer 4 options. Use 2 or 3 only when the question has fewer real answers, for example a yes/no question. Never pad with filler. Put the right one in a random position. Never mark an option as recommended.
- Use `multiSelect` when more than one option is right, and say so in the question.
- Use option previews when the options are code, for example "Which of these edits breaks the invariant?"

## Rules

- Each question has one clear answer that the diff and its callers settle.
- Never hint at the answer in the question text.
- A question that is hard to ask clearly points at code that is hard to understand. List it at the end as a candidate for simplification.

---
name: pr-comments
description: Walk the user through the doc comments a diff needs, one item at a time, suggesting five for each. Use when the user asks for doc comments, and in the Document step of pr-workflow.
---

# PR Comments

The user owns every doc comment. Suggest, never decide. Write doc comments
only, never inline comments.

## Steps

1. Read the diff. Find every item that now needs a doc comment, or whose doc
   comment the diff makes wrong. Keep the list to yourself.
2. Read 50 doc comments from the repo's own production code, or every one if
   it has fewer. Skip doc comments the diff adds. Take them in this order:
   a. The files the diff touches
   b. The modules the diff touches
   c. Items of the same kinds as the diff's items
   d. The rest, the most recently changed files first

   Production code is the code the repo's authors wrote and ship. It excludes
   vendored code, tests, CI and build scripts, benchmarks, examples and
   generated code.
3. Take the next item.
4. Open with a progress line, show the signature, and suggest 5 doc comments,
   labelled as options. Give more when the user asks.
5. Insert the user's choice verbatim, or the text the user writes. Then return
   to step 3.
6. Stop when the list is empty.

## Example

One turn, for a Rust diff with 7 items. `N` is the response number.

````
Doc comments [███░░░░] 3/7: `Cache::evict` (src/cache.rs:142)

```rust
pub fn evict(&mut self, now: Instant) -> usize {
```

Na. /// Removes entries older than the TTL and returns how many it removed.
Nb. /// Evicts expired entries as of `now`. Returns the number evicted.
Nc. /// Drops every entry whose TTL expired before `now`.
    ///
    /// Callers pass `now` so tests can control the clock.
Nd. /// Evicts expired entries. Runs in O(n) over all entries.
Ne. /// Removes stale entries and returns the count.
````

# Writing — plain English corpus

Real corrections from this repository, kept as before-and-after pairs.

Use this instead of extending a banned-word list. Every wording correction logged here used a phrase that no list contained, so banning each phrase after the fact never prevents the next one. Reading a few pairs teaches the shape of the mistake, which does transfer.

When a wording correction is logged during friction review, add the pair here. Only promote a word to the avoid-list in the skill body if the same word recurs across separate incidents.

## The shapes these mistakes take

Most entries below are one of five patterns. Recognising the pattern matters more than memorising the phrase:

- **Abstract noun for a concrete act** — "persistence" where the code says store
- **Umbrella compression** — one grand noun phrase standing in for the specific records or actions involved
- **Mechanism instead of outcome** — how the machinery works, where the reader wants what changes
- **Invented term** — a new name for something the codebase, or a sibling component, already names
- **What it is, not what to do with it** — a definition where the reader needs an instruction or an example

## Commit messages

**Before:** `retain exit codes for explicit tool errors`
**After:** `show exit codes when a tool fails`
**Why:** the first describes internal handling. The reader wants the visible change.

**Before:** `preserve bounded rollout evidence and provenance`
**After:** name the records involved, such as session links, completion events, and rollbacks
**Why:** "evidence and provenance" is an umbrella that hides which records the commit actually touched.

**Before:** `react to an injected heading level change`
**After:** `update when the heading level changes at runtime`
**Why:** "react to an injected X" is framework mechanics. The behaviour is that it updates.

## JSDoc, props, and reference descriptions

**Before:** `@param {object} options.name - The table name, used to persist column visibility.`
**After:** `@param {string|Ref<string>|Function} options.name - The table name as a plain value, ref, or getter. It identifies where column visibility is stored.`
**Why:** the type tag claimed a shape that was not true, and the description named a mechanism rather than what the caller passes.

**Before:** "Accessible name for the scroll region, read by screen readers and other assistive technology when no caption is provided."
**After:** "A short phrase describing what the table shows, for example Recent orders or Team members, so screen reader users can identify the scrollable region when the table has no visible caption."
**Why:** the first defines the prop. The second tells the caller what to put in it, with a concrete value.

**Before:** `the active storage ref for the current table identity`
**After:** `the user's stored preference`
**Why:** an invented compound noun for something with an ordinary name.

**Before:** `JSDoc token`, `source representation`, `a documented node`
**After:** the plain names the codebase already uses for those things
**Why:** inflated terms for concepts the codebase does not name that way.

## Test names

**Before:** `should start persistence when a table name becomes available`
**After:** `should start storing density once a table name becomes available`
**Why:** "persistence" matches no real API. The API is `useStorage`, so "storing" is both plainer and more accurate.

**Before:** `Exercise extraction shape, ordering, matching, errors, and live status.`
**After:** name what the tests prove about the extractor
**Why:** a run of abstract nouns that would describe almost any test file.

## Documentation and summaries

**Before:** "Persist column visibility when users change the table configuration."
**After:** "Store column visibility when users change the table configuration."
**Why:** "persist" is jargon for "store", and the real API says storage.

**Before:** `affordances`, `opens at its end`
**After:** `indicators`, matching the wording the sibling component already uses
**Why:** new terminology for a behaviour a sibling component had already named. Check the sibling before inventing a term.

## What stays unchanged

Making prose plainer must not cost accuracy. Keep every fact, name, number, file path, command, and identifier exactly as it was. If a term cannot be simplified without changing what the sentence claims, keep the precise term and explain it once.

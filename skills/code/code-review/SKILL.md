---
name: code-review
description: >
  Use this skill when reviewing code — a PR, a diff, an individual file, or existing code at a named path — or when receiving review feedback. Applies your conventions (accessibility, code-style, error-handling, frontend-security, web-performance) as a checklist, and covers how to give and receive feedback.
filePatterns: []
pathPatterns: []
---
# Code review

Reviews improve code collaboratively. Feedback is specific, actionable, grounded in code. Reviewers should understand what changed, why, and how it's maintained. If difficult, treat as maintainability issue.

## Giving a review

### Before reviewing

- Inspect changes summary-first: start with status, changed file names, and stats or numstat. Read a patch only for the selected file or hunk needed to assess a risk; do not print the entire diff by default.
- Reviewing existing code at a named path rather than a change? Skip the diff steps, take that path as the scope, and apply the same checklists to the code as it stands. Say what you covered, since there is no diff to bound it.
- Understand intent: what problem does this solve?
- Check scope: one thing or several?
- Before declaration review, name each changed file's responsibility and flag unrelated jobs or unclear boundaries.
- For repetition, compare explicit code, existing code, a helper, and a shared abstraction. Never accept inheritance or another file for line-count reduction alone.
- Load relevant language/framework skills.
- **Risk-aware focus**: high git churn or high fan-in → scrutinise more. Defects cluster in churn-heavy files; high fan-in = wider blast radius.

### Severity levels

| Level          | Meaning                                                                          | Must fix?         |
| -------------- | -------------------------------------------------------------------------------- | ----------------- |
| **Blocker**    | Incorrect behaviour, security issue, or accessibility failure that affects users | Yes, before merge |
| **Important**  | Violates a convention or pattern; degrades maintainability                       | Yes, before merge |
| **Suggestion** | Better approach exists; worth discussing                                         | Author's call     |
| **Nit**        | Minor style or clarity issue                                                     | Optional          |

### Checklist by area

**Correctness**

- Does it do what it claims?
- Edge cases handled (empty, null, 0, large input)?
- Error states at boundaries (user input, API)?
- Race conditions, off-by-one, unbounded loops, leaks?
- Is the same rule enforced in two places, such as client validation and a server schema, or a frontend option list and a backend enum? Do they still agree, or can the interface accept what the API rejects?

**Blast radius** (any change to shared code)

- What else calls or consumes the changed function, component, or type, and is every one of them updated?
- Do sibling paths handling the same concern get the same change, or does one quietly keep the old behaviour?
- Which cached values, stored IDs, error paths, or fallbacks still assume the behaviour that just changed?
- Say so explicitly when a change's blast radius could not be traced.

**Accessibility** (any UI change)

- Keyboard-reachable interactive elements?
- Labels, roles, ARIA correct?
- Colour contrast sufficient?
- No unsanitised `v-html`?

**UI quality** (any visible interface change)

- Does the existing product, platform, or design system remain the visual owner, using its established components, tokens, and patterns?
- Does the visual hierarchy make the primary task and the relative weight of secondary or destructive actions clear?
- Are relevant loading, empty, error, disabled, success, focus, keyboard, and touch states covered rather than only the happy path?
- Does the task remain usable at supported narrow and wide layouts, zoom levels, and content lengths through deliberate adaptation rather than shrinking alone?
- Are claims about layout, interaction, responsiveness, or visual quality backed by rendered or interactive evidence, with source-only conclusions labelled as such?

**Security** (input, auth, external data)

- User input validated/sanitised?
- Secrets server-side (not `VITE_`)?
- No open redirects from unvalidated params?
- Auth/authorisation checks match operation, not just route?
- No injection, path traversal, SSRF, unsafe deserialisation?

**Code style**

- Matches `code-style`: naming, comments, no speculative abstractions?
- Surgical: only needed changes?
- Organisation: each function/visitor owns one concern, no boolean flags swapping the algorithm, no switchboard helpers or logic duplicated across sibling files, clear control flow over clever tricks?

**Prose** (any changed comments, docstrings, test names, descriptions, metadata, or documentation)

- Confirm every value, callable, and type declaration has the required prose. Improve comments or docstrings that only repeat the name, signature, types, body, or mechanics; clear naming does not make omission acceptable.
- Read each complete prose unit without relying on the diff or symbol name. Confirm that it is true, says what the thing is or does, gives the reader information beyond the identifier or mechanics, and uses the simplest concrete wording.
- Review repeated sibling wording individually. A shared sentence shape is not evidence that each sentence fits its subject.
- After a point fix, reread the whole sentence, paragraph, or value. Do not approve a corrected phrase inside prose that remains inaccurate or unclear.

**Simplification** (this diff only)

- Has this change added unnecessary abstraction or machinery?
- Apply this to fixes too: dispatch, inheritance, or indirection must be simpler than visible repetition.
- Classify each flagged spot with exactly one tag: `[delete]` remove it; `[stdlib]` use the standard library; `[native]` use a platform feature; `[yagni]` avoid an unneeded addition; `[shrink-style]` use simpler code.
- For whole-repo debt, use `refactoring`'s **Technical debt triage** categories instead; these tags classify only the reviewed diff.
- For a fuller reuse/simplification/efficiency/altitude pass over a diff with dedicated review agents, use the built-in `/simplify` command instead of hand-rolling that pass here.

**Altitude**

- Does the changed module own each new concept, or was feature vocabulary pushed down to wherever the required data happens to live?
- Prefer direct caller-owned code when a shared layer would need caller-specific policy. Generalise only stable behaviour that the shared layer itself owns.

**Performance** (UI, list rendering, assets)

- Unnecessary re-renders or reactive side effects?
- Images sized and lazy-loaded?
- N+1 queries, missing indexes, unbounded queries, hot-path complexity?
- Long-lived objects built from closures or captured environments? They keep the entire enclosing scope alive for the object's lifetime, a memory leak when that scope holds large values. Prefer a class/struct that copies only the fields it needs.
- If claiming improvement, were before/after taken under same conditions (state, cache, throttling)? Warmed cache or narrow tests aren't real.

**Tests**

- Does the change include tests for new behaviour?
- Do existing tests still pass?
- For a library or package whose public surface is produced by a build step, source inspection alone does not establish the change works: name the built artefact checked, or state that built-output evidence was not obtained and what that leaves unproven. Inspect only the exact expected output path, do not list or read build trees, and ask before triggering a broad build.

### Tailoring by PR type

- **Bug fix**: root-cause correctness, regression test, no scope creep
- **New feature**: a11y, error handling, tests, API surface
- **Refactor**: behaviour preservation (tests pass before/after each step)
- **Dependency upgrade**: breaking changes, security advisories, bundle impact

### Giving feedback

- Prefix with severity: `[blocker]`, `[important]`, `[suggestion]`, `[nit]`.
- State what, why, ideally alternative.
- Ask before flagging unclear things as issues.
- Findings are for problems. When the change is clean, say so in one line, give the verdict, and stop. Do not invent small issues or record "this part is good" as a finding.

---

## Quick-reference checklist

PR-pasteable checklist: [`references/checklist.md`](references/checklist.md). PR description template: [`references/pr-description-template.md`](references/pr-description-template.md).

## Receiving a review

Read all feedback before responding; items may depend on each other.

**For each item:**

1. Restate understood feedback or ask if unclear
2. Verify against code; don't implement from memory
3. Evaluate if correct for stack/context
4. Respond with action or reasoned pushback, not agreement

**Push back when** suggestion breaks behaviour, lacks context, violates YAGNI, or conflicts with architecture. Use technical reasoning.

**If wrong:** state factually and proceed. _"You're right — it does [X]. Fixing now."_

**Implement one at a time.** Verify it works before next.

---

Blast radius, cross-boundary rule consistency, and the no-padding rule adapt ideas from `alamops/skills` (`skills/code-review`), MIT licensed.

The UI-quality checklist adapts ideas from Benjamin Stelzer's `scoville-ui-anti-ai-slop` skill, MIT licensed.

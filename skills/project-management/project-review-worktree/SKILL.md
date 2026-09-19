---
name: project-review-worktree
description: >
  Use this skill when reviewing uncommitted work before commit, especially requests like "review the working tree", "check this before commit", "is this ready to commit", or "review these changes against PROGRESS.md". Assesses correctness, completeness, plan alignment, maintainability, tests, docs, and commit readiness without editing files.
filePatterns: []
pathPatterns: []
---
# Project review worktree

Review uncommitted repository changes before commit. Default to review and recommendations only; do not edit files unless the user explicitly asks after the review.

## Scope

Look for regressions, missing work, weak tests, documentation gaps, and quality issues.

## Startup

Read `AGENTS.md`, `WORKSPACE.md`, diagnostics, `PROGRESS.md`, `git status --short`, and relevant changed files. If no workspace file exists, use `AGENTS.md`, package scripts, and nearby docs.

Gather routine orientation in one bounded call where possible. A supplied review packet may provide paths, prior results, exact commands, and unresolved risks; independently verify load-bearing claims instead of rediscovering unchanged facts.

Use `code-lookup` for structural questions. Use targeted reads; avoid generated, vendored, cached, build, dependency, coverage, and binary output.

## Skill routing

Load and apply `code-review`, `code-style`, and relevant language or framework skills. When the changes include comments, documentation, test or `describe` names, descriptions, metadata, or other prose, also load `writing` and read a few relevant pairs from its plain-English corpus before the craftsmanship pass. When changes affect a visible interface, also load `frontend-design` and `accessibility`; use `accessibility-audit` only when the request calls for an accessibility audit. Do not list an unloaded or unchecked skill as applied.

## Review method

1. Identify the task from the request, handoff, and changed files. List them with `git status --short`; do not stage or commit.
2. List the load-bearing review claims and the cheapest evidence that could settle each one.
3. When a safe, focused diagnostic or repro is already known, run it early and use its result to direct later reads. Run known non-mutating format and lint checks before manually reporting formatting findings. If command discovery is needed, inspect only enough context to identify it. Use `.agent/scripts/project-diagnostics.py --check <name>` when available.
4. Inspect changed files in context and find current lines, prioritising paths connected to failed, blocked, or uncovered claims. Component tests must mount the component under test, not substitute markup.
5. From the task-scoped diff, inventory every added or changed `const`/`let` and named function or class, including changed initializers and bodies. Check each against `code-style`; missing prose is a finding. Exclude unrelated user work.
6. Compare implementation and documentation with the plan, risks, verification, and generated-source boundary. Reference documentation must match code; roadmaps may describe future work.
7. Re-check PROGRESS.md's deferred or forward-looking notes (e.g. "optional hardening", "if a third caller ever needs this") against this diff. If the stated trigger condition is now met, treat it as a finding, not a resolved deferral.
8. Run any remaining cheap, justified checks raised by source inspection.
9. Run a separate cold craftsmanship pass over the current changed files after the correctness review. Inventory every changed prose unit, test or `describe` name, fixture or helper name and value, new structural grouping, and where each new declaration or setup call sits relative to its callers and the code it composes. For prose derived from an existing source, also inventory the claims, conditions, uncertainty, attribution, canonical terms, and working text contracts that must survive the edit. For visible UI, inventory the primary task and action hierarchy, canonical design-system choices, affected states, responsive transformations, and claims that need rendered or interactive evidence. Read each item without relying on task-file vocabulary, previous approval, or a sibling pattern to justify it. Check whether a reader can understand it without translating internal mechanics, whether its name describes observable behaviour and stays unambiguous next to the other names in its scope, whether its declaration sits where the reading order follows the data flow, whether protected meaning still matches its source, whether the UI remains usable across relevant states and layouts, and whether the added structure makes the file clearer. Existing precedent is context, not proof that the new item is good. After a craftsmanship finding is fixed, repeat this pass over the whole current chunk, not only the fix diff.
10. Lead with findings and evidence gaps. State when no must-fix issue exists.

Don't use `git diff` for routine self-review. For independent review, use targeted diffs or file reads when clearest, keeping output narrow.

## Finding standards

Use **Must-fix** for correctness, regression, generated-boundary, required-verification, misleading-plan, security, or data-loss issues; **Recommended** for material maintainability, tests, documentation, accessibility, UX, performance, or developer experience; **Nice-to-have** for non-blocking polish.

Give each finding a file and line where possible, problem, effect, and fix or decision. Mark speculation as conditional; do not invent requirements.

## Conventions

Check these against changed files and state which were checked:

- **Helper reuse** — reuse an existing helper, component, or command where it covers this
- **No switchboard drift** — a reused helper hasn't accumulated a boolean/option flag per new caller; that's a maintainability finding, not reuse
- **No single-use abstractions** — no composable, helper, or test utility with one caller
- **Simplest viable shape** — compare with direct code; new helpers, registry fields, callbacks, options, and indirection must make current use clearer, not prepare for possible reuse
- **Naming and sibling consistency** — uses neighbouring conventions where they remain clear and suitable; precedent does not excuse a weak name, a name that is ambiguous beside the other names in this file, or unnecessary structure
- **Declaration placement** — each new declaration and setup call reads in data-flow order, next to its callers and the code it composes, not appended after an unrelated block
- **Documentation coverage and wording** — use the inventory to find missing comments or JSDoc, then review communication separately. Read each changed comment, docstring, prop text, test name, description, metadata value, or documentation passage as a complete unit without relying on the diff or symbol name. Confirm that it is true, says what the thing is or does, gives the reader useful information beyond the identifier or mechanics, and uses the simplest concrete wording. Review repeated sibling wording individually. After a point fix, reread the whole sentence, paragraph, or value
- **UI craftsmanship** — for visible UI, preserve the canonical visual owner, make task and action hierarchy clear, cover relevant states and responsive transformations, and distinguish source inspection from rendered or interactive evidence
- **No out-of-contract changes** — every line traces to the task; adjacent improvements are findings, not edits

## Craftsmanship result

Before approval, report the declaration inventory, craftsmanship inventory, skills applied, ready or changes requested, and findings. The craftsmanship inventory lists each reviewed item by file and line; group clean items by file to keep the record compact. For source-derived prose and visible UI, include the protected meaning or working text contracts and the UI items checked. Do not approve with an incomplete inventory, unchecked convention, prose accepted only because it is present, or a previous craftsmanship verdict that has not been repeated after a related fix.

## Evidence status

Classify each load-bearing acceptance criterion:

- **Observed** — seen in a rendered browser page or the running app
- **Executed** — a specific assertion or repro step ran and would fail if this claim were false, not merely that the containing suite exited 0
- **Static** — read the code and reasoned about it
- **Blocked** — could not be checked here, with the reason

Rendered layout, visibility, overflow, and responsiveness are **Static** from jsdom or code reading. Do not approve unconditionally with a load-bearing Static or Blocked criterion: say what would settle it.

## Output

Use this shape:

```markdown
## Overall assessment

<Verdict, qualified when any load-bearing criterion is Static or Blocked.>

## Evidence status

- <criterion> — <Observed|Executed|Static|Blocked>. <Settling evidence, when needed.>

## Conventions checked

- <convention> — <pass or finding>.

## Declaration coverage

- `<file>:<line>` `<declaration>` — <the useful fact its prose gives the reader, or finding; presence alone does not pass>.

## Craftsmanship inventory

- `<file>:<line>` — <prose, name, value, grouping, source-fidelity item, or UI item reviewed; pass or finding>.

## Craftsmanship

- <ready or changes requested>. Skills applied: <skills>. <Findings, if any.>

## Must-fix issues before commit

- [Severity] `<file>:<line>` — <issue>. Fix: <action>.

## Recommended improvements

- `<file>:<line>` — <improvement>.

## Nice-to-have ideas

- <optional idea>.

## Suggested updates to PROGRESS.md

- <specific update>.

## Questions or assumptions

- <unknown>.

## Checks run

- `<command>` — <result>.

## Next step

<One concrete action.>
```

Use `None found.` or `None.` for empty sections, unless the user asks for another format.

### HCOM reviewer delivery

When this skill is used by an HCOM Reviewer, keep the complete output above as the durable `review` handoff record. The live HCOM message contains only the verdict, every actionable finding in one sentence, a compact verification summary with the first gap or failure, and the review record reference. Keep the declaration inventory and detailed evidence in the record; do not copy Scout receipts or the full review into the live message.

The source-fidelity and UI-craftsmanship checks adapt ideas from Benjamin Stelzer's `scoville-scribe-anti-ai-slop` and `scoville-ui-anti-ai-slop` skills, MIT licensed.

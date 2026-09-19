---
name: project-review-commits
description: >
  Use this skill when reviewing committed work across a Git range, especially every commit since the last tag. Assesses per-commit correctness, series coherence, verification, docs, and release readiness without editing files.
disable-model-invocation: true
---
# Project review commits

Review committed repository changes across a Git range. Default to review and recommendations only; do not edit files, stage, commit, tag, rebase, squash, merge, push, or otherwise rewrite history unless the user explicitly asks after the review.

## Scope

Assess whether the commit range is:

- correct and complete for the stated goal or release
- coherent as a sequence of commits
- safe to ship or build on
- covered by appropriate tests or verification
- aligned with project instructions, workspace facts, generated-file boundaries, changelogs, docs, and existing patterns

Look for bugs, regressions, incomplete follow-ups, misleading commit messages, missing generated output, stale docs, weak tests, security concerns, accessibility or UX regressions, performance risks, and commits that should be split, squashed, reordered, or followed by a fix.

## Startup

Read in order:

1. `<project-root>/AGENTS.md`
2. `<project-root>/WORKSPACE.md`, when present
3. `.agent/scripts/project-diagnostics.py --list`, when present
4. `PROGRESS.md` — recent completed work, risks, release notes, handoff
5. `git status --short`
6. Requested Git range, or last tag to `HEAD`
7. Commit messages, changed files, targeted diffs

Skip `WORKSPACE.md` if missing. Use `AGENTS.md`, package scripts, nearby docs as needed.

Gather routine orientation in one bounded call where possible. A supplied review packet may provide paths, prior results, exact commands, and unresolved risks; independently verify load-bearing claims instead of rediscovering unchanged facts.

Apply the `code-lookup` routing skill for structural questions. Use targeted reads; avoid generated, vendored, cached, build, dependency, coverage, or binary output.

## Range selection

1. If the user provides an explicit range, review that range.
2. Otherwise, resolve the last reachable tag with `git describe --tags --abbrev=0`.
3. Review `last-tag..HEAD` when a tag exists.
4. If no tag exists, stop and ask whether to review all history, a specific range, or the current branch against its merge base.
5. If the range is empty, say so and stop.

Before reviewing, check `git status --short`. If uncommitted files exist, state they are outside this review and recommend `project-review-worktree`. Continue unless the dirty worktree makes evidence ambiguous.

## Skill routing

Always apply `code-review` standards. Load additional skills only when the touched files or diff contents make them relevant:

- `frontend-security` for user input, auth, tokens, secrets, sanitisation, CSP, redirects, or external data
- `accessibility` or `accessibility-audit` for UI, HTML, components, forms, keyboard interaction, colour, ARIA, or interface copy
- `web-performance` for runtime performance, asset loading, bundle size, Core Web Vitals, rendering, or reactivity cost
- `typescript`, `vue`, `vue-router`, `vue-pinia`, `vue-pinia-colada`, or `vue-vite` for matching Vue/TypeScript files and APIs
- `swift` or `swift-ui` for Swift or SwiftUI changes
- `bash` for shell scripts, hooks, installers, environment files, or command snippets
- `dependencies` for package additions, removals, upgrades, lockfile changes, or dependency recommendations
- `writing`, `writing-readme`, or `writing-copy` for prose, README, documentation, or UI copy changes
- `test`, `test-unit`, or `test-e2e` for test strategy, test files, coverage gaps, or browser checks

If a relevant skill is unavailable, state that once and continue with the closest applicable checklist.

## Review method

1. Identify the intended goal from the user request, branch name, `PROGRESS.md`, release notes, commit messages, and changed files.
2. List the reviewed range and commits oldest to newest. Do not stage or commit.
3. List the load-bearing review claims and the cheapest evidence that could settle each one.
4. When a safe, focused diagnostic or repro is already known, run it early and use its result to direct later reads. If command discovery is needed, inspect only enough context to identify it. Use `.agent/scripts/project-diagnostics.py --check <name>` when available.
5. Inspect each commit enough to understand its behaviour, risk, and relationship to surrounding commits, prioritising paths connected to failed, blocked, or uncovered claims.
6. Compare implementation with the stated goal, expected commits, docs expectations, generated output, risks, and verification guidance.
7. Check whether each commit is internally coherent and whether the series tells a truthful story.
8. Check for follow-up commits that fix earlier mistakes; report the final risk, not just the intermediate state.
9. Check generated/source boundaries and stale generated output.
10. Run any remaining cheap, justified checks raised by source inspection.
11. Lead with findings. If there are no must-fix issues, say so clearly and note any remaining verification gaps.

Use `git show --stat --oneline --no-renames <commit>` or targeted `git show -- <path>` reads when they answer the review question. Avoid printing full diffs for large commits; narrow by path or pattern.

## Finding standards

Prioritise concrete issues:

- **Must-fix** — correctness bugs, regressions, broken generated/source boundaries, missing required verification, release-blocking mismatch, security, accessibility failure, data-loss risk, misleading history
- **Recommended** — maintainability, test, docs, accessibility, UX, performance, commit boundaries, developer experience improvements
- **Nice-to-have** — polish, simplification, or broader ideas with clear value but no release-blocking need

Each finding includes: commit reference, file/line reference, what's wrong, why it matters, concrete fix or decision needed.

Mark speculative ideas conditional. Don't invent requirements or recommend rewriting when a follow-up commit is safer.

## Output

Use this shape:

```markdown
## Overall assessment

<Is the reviewed range broadly safe? Name the main reason.>

## Range reviewed

- Base: `<tag-or-range-start>`
- Head: `<head>`
- Commits: <count>
- Dirty worktree: <yes/no, and whether uncommitted files were excluded>

## Must-fix issues

- [Severity] `<commit>` `<file>:<line>` — <issue>. Fix: <specific action>.

## Per-commit findings

- `<commit>` — <finding or "No issues found.">

## Series-level concerns

- <cross-commit issue, generated/source drift, sequencing problem, or release concern>.

## Recommended improvements

- `<commit-or-file>` — <improvement and reason>.

## Nice-to-have ideas

- <optional idea, labelled if exploratory>.

## Questions or assumptions

- <unknown that affects confidence, limited to an observed failure or a concrete unresolved scenario traced from changed lines to a real consumer or public contract>.

## Checks run

- `<command>` — <result>.

## Next step

<One concrete action: fix a must-fix item, run a missing check, prepare a follow-up commit, or approve the range.>
```

If a section has no items, say `None found.` or `None.` Do not omit sections unless the user's requested format differs.

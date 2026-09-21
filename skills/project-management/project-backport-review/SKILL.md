---
name: project-backport-review
description: >
  Use this skill when comparing a client/consumer project against the boilerplate template it started from, to find backport candidates and then improve boilerplate itself for the next project.
---
# Project backport review

Compare a client/consumer project against the boilerplate template it started from. The failure this skill prevents is a one-directional, ad hoc diff: skimming the consumer project for ideas, missing the second pass that improves boilerplate itself, and backporting client-specific code that has no business in a shared template.

Default to analysis and recommendations only. Do not edit boilerplate files until the user approves specific items — boilerplate changes affect every future client project, so treat them as higher-stakes than a normal repo edit.

## Scope

Two repos, two passes, in order:

1. **Consumer → boilerplate**: what exists in the consumer project that is better, simpler, more complete, or better-structured than the boilerplate equivalent, and is genuinely reusable (not client-specific).
2. **Boilerplate self-review**: assuming pass 1's adoptable items are merged, what else would make boilerplate the best possible starting point for the _next_ client project — gaps, defaults, structure, setup steps.

Do not use this skill for:

- an unrelated external artefact (blog, docs, someone else's `AGENTS.md`, an unconnected repo) — use `project-learn-from-source`
- auditing boilerplate alone with no consumer project as a comparison point — use `project-audit`
- reviewing a specific diff or PR — use `code-review`

## Startup

1. Confirm both repo paths/roots are available as working directories (or ask for the missing one).
2. Read `AGENTS.md` and ordinary docs for both repos if present, and inspect `agent-run list --json`, to understand each project's intended shape and documented deviations from boilerplate.
3. Check whether boilerplate exposes Boilersuit generators (`.boilersuit/generators/`). If a candidate improvement is something a generator should produce rather than a static file, flag it for `boilersuit-generator-authoring`, not a plain file edit.
4. For structural questions, use a code index when available to find definitions and callers before deciding; otherwise use a scoped search. For the full lookup workflow, see `code-lookup`. Scope reads to config, scripts, component/composable patterns, CI, and docs — skip generated output, lockfiles, and vendored/build directories in both repos.

## Review method

1. Enumerate the areas that matter most for a template repo: build/tooling config, lint/format/test setup, CI, scripts, component and composable patterns, folder structure, dependency choices, docs (`AGENTS.md`, `README.md`), agent-run registrations, accessibility/security defaults, and any setup/init flow.
2. For each area, diff consumer against boilerplate and classify every difference as one of:
   - **client-specific** — business logic, branding, domain code; never backport
   - **local deviation** — consumer diverged from boilerplate for a reason that doesn't generalise; note but don't backport
   - **backport candidate** — genuinely better, simpler, or more complete, and reusable across future client projects
3. For each backport candidate, judge: does it belong as a static template file, a Boilersuit generator, a documented setup step, or a default dependency/config choice?
4. Once pass 1's candidates are set, do pass 2: with those changes assumed merged, look at boilerplate on its own and find further gaps or improvements a fresh client project would benefit from having by default — even ones with no counterpart in the consumer project.
5. Prefer small, reviewable, high-leverage changes over broad restructuring. Note broad ideas as follow-ups rather than bundling them into the same change set.
6. Push back on anything that adds ceremony, a new dependency, or an abstraction without a clear payoff for the _average_ future client project — boilerplate optimises for the common case, not this one client's edge case.

## Output

Use this shape unless the user asks for a different format:

```markdown
## Backport candidates (consumer → boilerplate)

- [Recommended] <item>. Where: <consumer path>. Why it's better: <reason>. Boilerplate shape: <static file / generator / doc / default>.

## Local deviations (not backported)

- <item>. Why it doesn't generalise: <reason>.

## Boilerplate-only improvements (pass 2)

- [Recommended] <item>. Why it helps the next project: <reason>. Files/generators involved: <path(s)>.

## Ideas rejected

- <idea>. Why: <cost, mismatch, low value, or duplicates existing boilerplate behaviour>.

## Evidence checked

- Consumer project: <repo, paths inspected>
- Boilerplate: <repo, paths inspected>

## Next step

<One concrete action: approve specific items to implement, choose between options, or close with no action.>
```

If a section has no items, say `None found.` Keep the list proportional to what actually differs; do not pad it to make the comparison look thorough.

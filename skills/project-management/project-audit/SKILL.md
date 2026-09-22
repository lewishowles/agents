---
name: project-audit
description: >
  Use this skill when auditing a project for setup drift, stale generated output, missing diagnostics, command-safety gaps, or agent-readiness issues. Covers AGENTS.md, agent-run registrations, global project-checks and friction commands, PROGRESS.md handoff health, validation commands, and generated/source boundaries.
---
# Project audit

Audit project agent-readiness and maintenance drift. Default to findings and recommendations, not implementation.

## Scope

Audit:

- project instruction health (`AGENTS.md`)
- project command registrations (`agent-run`)
- globally installed `project-checks` and `friction` commands
- diagnostics discoverability and command safety
- generated/source boundaries
- `PROGRESS.md` handoff quality when multi-session work is active
- setup drift after this configuration repo changes

Do not turn this into broad code-quality review. Use `code-review` for code diffs and `accessibility-audit` for UI/WCAG audits.

## Startup

Read in order, stopping when you have enough context:

1. `<project-root>/AGENTS.md`
2. `agent-run list --json`
3. `project-checks-repo-context` output
4. `project-checks-generated-file-guard` output
5. `PROGRESS.md` handoff, when active work or session continuity is part of the audit

If agent-run has no registrations, inspect `AGENTS.md`, package scripts, and ordinary docs, then use `agent-run detect --json` to preview likely commands.

## Tooling checks

When these scripts exist, prefer them over manual inference:

```sh
agent-run list --json
project-checks-repo-context
project-checks-generated-file-guard
```

Use `agent-run run <name> --json` for a registered check. Use `agent-run run --json -- <argv>` only for a one-off check, and keep manual-only commands with the human.

If generated-file guard reports findings, treat them as high priority: review may target generated or stale output.

## Findings

Lead with findings ordered by risk:

- **High** — unsafe commands, missing project command registrations, generated/source mismatch, stale diagnostics, broken setup scripts
- **Medium** — incomplete project instructions, missing progress handoff for active multi-session work, stale generated paths, unclear package manager/runtime facts
- **Low** — minor wording drift, convenience tooling not installed, non-blocking docs gaps

Each finding includes:

- exact file or command involved
- why it matters for future agents
- concrete fix

## Output

Use this shape:

```markdown
Findings

- [High] <path or command>: <problem>. Fix: <action>.

Checks run

- `<command>` — <result>

Recommended next step

<one concrete action>
```

If no issues found, say so and list checks run. Do not invent improvements.

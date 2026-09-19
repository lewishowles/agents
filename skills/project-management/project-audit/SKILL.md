---
name: project-audit
description: >
  Use this skill when auditing a project for setup drift, stale generated output, missing diagnostics, command-safety gaps, or agent-readiness issues. Covers WORKSPACE.md, .agent/scripts tooling, PROGRESS.md handoff health, validation commands, and generated/source boundaries.
filePatterns: []
pathPatterns: []
---
# Project audit

Audit project agent-readiness and maintenance drift. Default to findings and recommendations, not implementation.

## Scope

Audit:

- project instruction health (`AGENTS.md`)
- factual workspace coverage (`WORKSPACE.md`)
- project-local agent tools under `.agent/scripts/`
- diagnostics discoverability and command safety
- generated/source boundaries
- `PROGRESS.md` handoff quality when multi-session work is active
- setup drift after this configuration repo changes

Do not turn this into broad code-quality review. Use `code-review` for code diffs and `accessibility-audit` for UI/WCAG audits.

## Startup

Read in order, stopping when you have enough context:

1. `<project-root>/AGENTS.md`
2. `<project-root>/WORKSPACE.md`
3. `<project-root>/.agent/scripts/repo-context.py` output, if present
4. `<project-root>/.agent/scripts/generated-file-guard.py` output, if present
5. `<project-root>/.agent/scripts/project-diagnostics.py --list`, if present
6. `PROGRESS.md` handoff, when active work or session continuity is part of the audit

If `WORKSPACE.md` is missing, report it and inspect `AGENTS.md`, package scripts, and nearby docs instead.

## Tooling checks

When these scripts exist, prefer them over manual inference:

```sh
.agent/scripts/repo-context.py
.agent/scripts/generated-file-guard.py
.agent/scripts/project-diagnostics.py --list
```

Do not run `.agent/scripts/project-diagnostics.py --all` unless asked for broad verification. For focused audits, `--list` is enough unless a specific check matters to a finding.

If generated-file guard reports findings, treat them as high priority: review may target generated or stale output.

## Findings

Lead with findings ordered by risk:

- **High** — unsafe commands, missing workspace file in an active project, generated/source mismatch, stale diagnostics, broken setup scripts
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

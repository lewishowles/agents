---
name: project-setup
description: >
  Use this skill to start a new project or feature — explores the repo, asks clarifying questions, and creates the initial plan as progress CLI records before any implementation begins.
---
# Project setup

Start a new project or feature. Create the initial plan as `progress` CLI release, task, and chunk records after exploration and discussion; do not implement until the plan is reviewed.

## Progress records

The `progress` CLI stores project state in SQLite. Use release, task, chunk, discovery, decision, and context records for plan, status, queue, roadmap, and handoff state.

## Project facts

Check `<project-root>/AGENTS.md`, ordinary docs, and `agent-run list --json` before planning. Use AGENTS.md for durable project facts and gotchas, ordinary docs for usage, and agent-run for commands and manual-only rules.

Use `agent-run detect --json` to preview likely commands and record their names in the plan. Register a missing command during implementation or verification with `agent-run detect --add <name>` (repeatable) or `agent-run detect --all`, then report what you registered. Do not register commands during planning or review. Use `agent-run run <name> --json` for verification and `agent-run run --json -- <argv>` for one-off commands. Manual-only commands stay with the human.

### Migrate legacy project guidance

For a repo that still has `WORKSPACE.md`, `AGENT_CAPABILITIES.md`, or a `.agent/scripts/project-diagnostics.py` link, move its facts before deleting anything:

1. Read the legacy file. Move durable gotchas and forbidden operations to `AGENTS.md` and usage notes to ordinary docs. Skip anything the repo's own files already say.
2. Register commands with `agent-run detect --json`, then `agent-run detect --add <name>` (repeatable) or `agent-run detect --all`. For each command the legacy file said a person must run, mark it with `agent-run edit <name> --manual` (or register it with `agent-run add <name> --manual -- <argv>` if detect did not find it), then confirm `manual: true` in `agent-run list --json`.
3. Replace any `project-diagnostics.py` instructions in `AGENTS.md` or docs with the matching agent-run commands.
4. Trash `WORKSPACE.md`, `AGENT_CAPABILITIES.md`, the `.agent/scripts/project-diagnostics.py` link, and any old `.agent/scripts/repo-context.py`, `.agent/scripts/change-impact.py`, `.agent/scripts/generated-file-guard.py`, or `.agent/scripts/markdown-claims.py` links.

## Workflow

1. **Explore** — read repo, identify patterns, tech, relevant files; check project state with `progress next --json` and inspect `AGENTS.md`, `agent-run list --json`, `CONTEXT.md`, `README.md`, and optional `PROGRESS.md`. Use the returned task and chunk records as the full contract.
2. **Ask** — identify all known decision-blocking ambiguities, constraints, tradeoffs, and alternatives, then ask them together. Do not cap this initial set. Ask further questions only when an answer reveals a material new unknown.
   - For ambiguous or consequential work, group questions by dependency. In each round, ask every question whose prerequisites are settled, give a recommended default, then reassess after the reply. Do not ask downstream questions that assume an answer still open.
3. **Discuss** — if multiple approaches exist, present them; don't pick silently
4. **Plan** — create the initial release, task, and chunk records with the `progress` CLI
5. **Wait** — do not start until the plan is reviewed and approved. Present the returned task and chunk contract in chat so the user can challenge its fields or answer its open questions. A genuinely trivial backlog item can just be shown directly.

## Subagent delegation (optional)

After plan approval, consider delegating implementation tasks to subagents when:

- The plan has 3+ independent tasks that don't share files
- Tasks are well-specified with clear acceptance criteria
- The work is mechanical: scaffolding, repeated pattern changes, test writing

**Do not delegate when:**

- Tasks share files or have high interdependency
- Single-file changes or quick fixes
- The task requires nuanced judgment or architectural decisions
- The agent runtime doesn't support subagents

### Review gate

Delegate exactly one implementation chunk at a time. Do not delegate or begin the next chunk in the same pass, even when files are independent. Complete the current chunk record, present it, and stop; the next chunk starts in a fresh session.

For each delegated task:

1. **Delegate** — give the subagent the goal, rationale, constraints, acceptance criteria, and relevant file paths from the task record
2. **Review** — inspect the subagent's output against acceptance criteria; do not trust blindly
3. **Approve or request changes** — if output is correct, proceed; if not, send specific feedback
4. **Hand off** — after approval, present the verified result and wait for the user's acceptance before delegating the next task

After two comparable failures, escalate to a more capable agent or resume in the main session.

Enables autonomous multi-hour execution while keeping the main agent as architect and reviewer.

**Token tradeoff:** subagents re-read files the main agent already has in context. Use when the plan is too large for one context window.

## Planning principles

- A task record owns a coherent feature or outcome and may contain several ordered chunks. Each chunk has one reviewable outcome, coherent files, and focused verification. Create a separate task only for independently schedulable feature work, decisions, dependencies, or release boundaries, not merely because the feature needs multiple chunks.
- Apply the `project-plan-task` task-boundary gate before creating a standalone task.
- For a multi-chunk task, create one progress chunk per reviewable outcome; work only on the first incomplete chunk unless the user asks for all.
- Apply the `project-plan-task` review-size gate to every chunk: one primary review question and a soft ceiling of three substantive files.
- Multiple small sections over one large one; each independently reviewable
- "Files likely to change" reduces re-exploration in future sessions
- Record every known section as a chunk. Later chunks may stay concise until work starts, but their boundaries and order belong in `progress` as soon as they are known
- Record why the task is split the way it is in `--split-rationale`; a single-chunk task must explain why the substantive-concern inventory found only one reviewable concern
- Store session handoff in the progress CLI context record with `progress context set`; start with `progress next --json` and stop after the returned task and chunk unless deeper context is genuinely needed.

### Planning-quality gate

Before asking for approval on any substantive task or feature contract, self-check it against: repository truth, contract, boundary, altitude, failure and recovery states, acceptance evidence, and verification. Leave a strong contract unchanged. Invoke `project-review-task` explicitly when a high-risk or high-ambiguity contract warrants an independent pass, or once a genuine second reviewer is available — a solo self-check by the authoring model is not a substitute.

Apply the clear planning language gate from `docs/progress-format.md` to task records, chunks, and feature specs. Write for a reader who does not share the investigation context: state the problem first, use direct statements with a clear subject and action, keep one requirement, decision, recommendation, or question per bullet, explain unfamiliar terms, separate confirmed requirements from recommended defaults and unresolved questions, and make acceptance criteria observable. Preserve exact APIs, paths, commands, edge cases, constraints, failure behaviour, verification requirements, and technical decisions. If clarification would require a new product or architecture decision, leave it unresolved and use `needs-decision` instead of guessing.

## Feature specs

Use linked specs only for larger spikes or ambiguous features. Skip small changes, bug fixes, routine docs, or single-section work.

Specs are per-feature/spike under `.agent/specs/<feature>.md`, linked from the task record. The spec carries heavier context, read only when its task is active.

Use this outline when a spec is warranted:

```markdown
# <Feature or spike name>

## Why now

Why this matters now, trigger, and consequence if not done.

## Problem

User or system problem.

## Goals

- Outcome that must be true

## First usable version

Smallest end-to-end path that solves the problem, including deliberate manual steps.

## Current status

Optional; omit if obvious or the spec is new. What's already done vs what's still outstanding, so a fresh agent can gauge progress without reading history.

## Non-goals

- Work deliberately out of scope

## Proposed approach

Intended solution shape, including important alternatives or tradeoffs.

## High-cost assumptions

Optional. Assumptions most costly if wrong, and the earliest evidence that can test them.

## Entry point

Optional; omit if obvious. Where an agent with zero prior context should start reading — the first file, command, or concept to look at.

## Files to inspect

Optional; omit if obvious. Files most relevant to understanding or continuing this work.

## API, schema, or interface

Commands, routes, data shape, UI states, or public contracts affected.

## Decisions

Optional; omit if none yet. Choices already made and why, so they aren't re-debated.

## Open questions

Optional; omit if none. What's still unresolved.

## Acceptance criteria

- Observable condition that proves the work is done

## Risks

- Risk, uncertainty, or dependency to monitor

## Verification

Focused checks, manual review, or evidence needed before handoff.
```

When permanent decisions emerge, move them to `AGENTS.md`'s `## Need to know` section, architecture docs, user docs, or ADR only when ADR criteria are met. `AGENTS.md` is read every session and never gets compacted, so it's the right home for a fact once it proves durable.

## CONTEXT.md — domain glossary

Root `CONTEXT.md` is pure domain glossary: canonical names, names to avoid, resolved ambiguities. Not spec, scratch pad, or guide.

Create lazily as terms emerge. Add entries when agreed, not in batches.

Each entry:

```markdown
**Term** — one-sentence definition. _Avoid_: synonyms or overloaded words.
```

Use vocabulary from `CONTEXT.md` in code, comments, issue titles, ADRs. Surface conflicts instead of picking silently.

_Pattern inspired by [mattpocock/skills](https://github.com/mattpocock/skills) (MIT)._

## PROGRESS.md prose

`PROGRESS.md` is optional and lives at the project root. It contains only freeform prose under `## Upcoming work` and `## Parking lot`. Do not use it for task status, active chunks, release roadmaps, queue order, decisions, discoveries, or session handoff. Those records belong to the `progress` CLI. See `docs/progress-format.md` for the CLI data model.

## Upcoming work

Brief bullets for backlog items with no task or spec record yet. Detailed planning, and a task record, happen when work starts.

## Parking lot

Ideas and concerns not belonging to the current section.

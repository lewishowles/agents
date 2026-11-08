---
name: project-review-progress
description: >
  Use this user-invoked skill when reviewing a project's whole progress task list or roadmap, especially requests like "review the progress plan", "check the task list", or "what is missing from the plan". Checks the progress records and project direction, reports exact repair commands, and applies only fixes the human approves.
disable-model-invocation: true
---

# Project review progress

Review the whole project plan in `progress` before changing any records. This skill covers the task list; use `project-review-task` for one task and `project-continue` to resume work.

## What to read

1. Read the project rules in `AGENTS.md` and the registered commands with `agent-run list --json`.
2. Run `progress export --json` once. It includes the project, releases, all tasks and their dependencies, chunks, discoveries, decisions, inbox notes, and project and task handoffs, including completed work. Each task lists its prerequisites under `dependency_ids`, and handoffs sit under `context`. Use this as the plan instead of stitching together list commands.
3. Run `progress doctor`. Report its missing-field findings. Do not repeat its checks for a release overview, a task overview, done criteria or split rationale, a chunk description, or a pending or active chunk's review question.
4. Read `PROGRESS.md` only if it exists. It holds optional freeform notes, so flag only notes that contradict the progress records. Read related specs, docs, or source only when a specific finding needs evidence.

For structural code questions, use the `code-lookup` workflow. Keep reads targeted and avoid generated or dependency output.

## What to check

Judge whether the task list gives a fresh agent a clear next step, stop point, expected files, verification, and unresolved decisions. Check the whole list for:

- Tasks queued before their dependencies, dependencies that are missing or no longer fit, and work ordered by age instead of value
- Chunks too large for one reviewable commit, or review questions joining concerns a reviewer could accept separately
- Done tasks that still have pending or active chunks. `progress task complete` refuses to finish a task with open chunks, but older records, or a chunk added after the task was completed, can still show it
- Project or task handoffs pointing to missing or finished work; use current records over stale handoffs, as `project-continue` does for one selected task
- Tasks still titled `Needs planning:` after they are fully planned, and tasks with no chunks or only some chunks planned that lack the prefix
- Decisions with no condition for reopening them when the relevant facts change
- Gaps in project direction, architecture, UX, accessibility, maintainability, testing, performance, documentation, developer experience, release safety, and operational risk
- Low-value, speculative, or overcomplicated work to remove, park, or defer

Challenge the planned work, not only its wording. Suggest broader ideas when they materially improve the project, and label them optional unless needed for correctness or quality. Do not invent requirements; mark recommendations that depend on missing context as conditional.

## How to report and fix

Lead with an assessment of the project direction and whether the task list is ready for multi-session work. Group findings as **Must address**, **Recommended**, or **Optional**. For every finding, name the affected record or note, explain its impact, and give the exact `progress` command that would fix it, with real IDs and replacement text rather than placeholders. For a conflicting `PROGRESS.md` note, give the exact prose edit separately. If a safe fix depends on a human choice, show the command for each viable choice and recommend one. Include the relevant `progress doctor` findings, checks run, assumptions, and the next decision. Say `None found.` when a group has no findings.

Do not run any proposed fix during the review. Ask which findings the human approves, then run only those approved commands. Re-read the affected records after each approved change and report what changed. If the CLI cannot represent a requested fix, explain the gap instead of editing its database or inventing a parallel plan.

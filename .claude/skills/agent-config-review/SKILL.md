---
name: agent-config-review
description: >
  Use this repo-local skill when reviewing the Configuration/Agents repository as an agent behaviour system: token footprint, global-rule placement, skill boundaries, validation coverage, generated-output drift, and setup ergonomics.
do-not-use-when:
  - Auditing a normal project for agent-readiness; use project-audit instead
  - Reviewing code changes, PRs, commits, or worktrees; use the project review skills instead
  - Implementing a specific rule, skill, hook, or script change
---

# Agent config review

Review this repository as a configuration system, not application code. Failure mode: treating rules, skills, hooks, validation scripts in isolation, missing context cost, duplicated guidance, unclear boundaries, validation gaps.

Repo-local to `~/Dev/Configuration/Agents` — doesn't move into `skills/` tree; it reviews the system creating shared skills.

## Contract

After loading, review whether the configuration repo is lean, well-partitioned, and self-validating before proposing changes.

## Review scope

Assess:

- Token footprint: always-loaded rules, skill descriptions, generated output, duplicated guidance
- Rule vs skill placement: task-specific guidance in always-on rules?
- Skill taxonomy: overlapping skills, missing exclusions, vague descriptions, manual-only skills needing triggers, name-only targets
- Validation coverage: generated output, manifests, docs tables, hook sync, setup drift, direct edits
- Repo ergonomics: `AGENTS.md`, `PROGRESS.md`, setup docs, repo-local skills, agent-run
- Friction evidence: grounded in repeated failures, not speculative neatness

Do not assess product code quality, UI accessibility, dependencies, or repository hygiene unless directly affecting agent configuration behaviour.

## Startup

1. Read root `AGENTS.md`. This repository is a configuration source, not a downstream project.
2. Load `.claude/skills/agent-config/SKILL.md` for repo structure.
3. Entry points: `scripts/validate.sh` and `scripts/sync.sh`. Don't run `scripts/agent-tools/repo-context.py` against this repo. It defaults to target projects and is a downstream shim, not a way to inspect Configuration/Agents itself.
4. Inspect `PROGRESS.md` when active work or unfinished validation may affect recommendations.
5. Use targeted searches. Avoid broad reads of `dist/`, generated docs, external references, or logs unless findings point there.

## Review passes

### Token footprint

Check:

- Always-loaded vs triggered-only content
- Global rules repeating skill details?
- Skill descriptions longer/broader than needed for discovery?
- Canonical skill instructions duplicating or drifting from the rule and hook contracts?
- `skillOverrides` or target-specific distribution reducing cost without hiding essentials?

Reduce tokens only while preserving reliability. Don't move guidance from global rules if it must apply every turn.

### Frontier-model migration

When the default model family changes, review the instructions for semantic drift as well as size. Check always-loaded rules, relevant skills, and tool descriptions for:

- model-specific settings that the new model no longer supports
- instructions that contradict each other
- mandatory scratchpads, reasoning templates, or fixed thinking procedures
- verification or thoroughness wording that causes repeated reasoning or tool calls

Use current friction and representative tasks to decide whether a finding causes a real problem. Preserve safety, permission, recovery, and evidence requirements even when their wording is emphatic. Do not remove or weaken guidance solely because a prompt audit flags it.

Compare any proposed change against the existing behaviour on representative tasks. Record observed quality and tool use, and record latency or usage only when the runtime exposes them. Treat external prompt-audit tools as evidence rather than authority, and verify their source, licence, dependencies, and permissions before use.

### Rule and skill boundary

Use this decision test:

- Always applies, regardless of task: keep in `rules/`
- Applies only to a task type, file type, or user phrase: move to or strengthen a skill
- Applies only in this repository: keep repo-local, under `.claude/skills/` with an `.agents/skills/` symlink when Codex should see it
- Applies only to generated output: validate it with scripts rather than relying on prose reminders

Flag guidance that mixes these categories in one section.

### Skill taxonomy

Check:

- Missing `do-not-use-when` clauses where skills could misfire?
- Broad descriptions causing unnecessary loading?
- Overlapping skills needing clearer references or split responsibilities?
- Manual-only skills that should have trigger phrases (users naturally ask)?
- Task flows that should reuse existing review, writing, testing, debugging skills?

Tighten existing skills over creating new ones unless the failure mode is specific, repeated, and uncovered.

### Validation and generated boundaries

Check:

- Every generated output has source-of-truth and drift check?
- Validation catches direct edits to generated files?
- Setup scripts, docs tables, symlink topologies match documented state?
- Diagnostics discoverable via expected entry point?
- Validation output compact for agent use?

Prioritise: generated/installed/documented state divergence silently.

### Evidence and friction

Evidence order:

1. Direct file contents or script output
2. Validation scripts and fixtures
3. `PROGRESS.md` decisions and discoveries
4. Grouped friction from `friction summary --json`
5. Inferred risk (clearly labelled)

Don't overfit to single annoyances. Weight repeated friction, missing validation, expensive always-loaded guidance.

## Output

Lead with findings, ordered by effect on agent reliability and token cost:

```markdown
Findings

- [High] <area>: <problem>. Matters: <effect>. Fix: <action>.
- [Medium] <area>: <problem>. Matters: <effect>. Fix: <action>.
- [Low] <area>: <problem>. Matters: <effect>. Fix: <action>.

Removals

- <file and exact guidance to cut> — <what it duplicates, or why it is stale>.

Checks run

- `<command>` — <result>

Recommended next step

<one concrete action>
```

`Removals` is required, not optional. Name each cut with the evidence for it, or state plainly that nothing should be cut and why. Never omit the element: a review that only adds and adjusts is how guidance grows unnoticed.

No findings: say so plainly and list supporting checks.

Analysis only: don't edit. For implementation requests: stop after one reviewable chunk and provide a Conventional Commit message.

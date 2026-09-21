---
name: project-review-progress
description: >
  Use this skill when reviewing an existing PROGRESS.md plan or project roadmap, especially requests like "review PROGRESS.md", "check the plan", "is this a good plan", or "what is missing from the progress plan". Assesses both PROGRESS.md as an execution plan and the quality of the project direction it describes, without editing files.
disable-model-invocation: true
---
# Project review progress

Review an existing `PROGRESS.md` before changing it. Assess both the document as an execution plan and the quality of the project direction it describes.

Default to review and recommendations only; do not edit files unless the user explicitly asks after the review.

## Scope

Evaluate two layers:

- **Plan quality** — whether `PROGRESS.md` is clear, coherent, sequenced, resumable, split into committable chunks, and specific about verification
- **Project judgement** — whether the planned work itself is likely to produce the strongest version of the repo, or whether it is missing important work, overbuilding, under-specifying, sequencing poorly, or carrying hidden risk

Suggest broader ideas that could materially improve the project, even if absent from the plan. Label optional/exploratory unless necessary for correctness, maintainability, accessibility, security, performance, developer experience, or long-term quality.

Don't invent requirements or recommend complexity for its own sake. Mark ideas dependent on missing context as conditional.

## Startup

Read in order, stopping when you have enough context:

1. `<project-root>/AGENTS.md`
2. `agent-run list --json`
3. `PROGRESS.md`
4. Related specs, docs, source, or generated-file facts only when referenced or needed for evidence

If agent-run has no registrations, use `AGENTS.md`, package scripts, and ordinary docs as needed.

For structural questions, use a code index when available to find definitions and callers before deciding; otherwise use a scoped search. For the full lookup workflow, see `code-lookup`. Use targeted reads; avoid generated, vendored, cached, build, dependency, coverage, or binary output.

## Review method

1. Identify the project goal, active work, upcoming milestones, expected commits, risks, decisions, discoveries, and session handoff.
2. Check whether the plan is actionable for a fresh agent: next step, stop point, verification, files likely to change, and open questions.
3. Check whether work is sequenced by dependency and value, not just by when ideas were added.
4. Check whether each chunk can become a coherent commit with a clear Conventional Commit message.
5. Look for gaps in architecture, UX, accessibility, maintainability, testing, performance, documentation, developer experience, release safety, and operational risk.
6. Look for low-value, speculative, or overcomplicated work that should be removed, parked, or deferred.
7. Recommend specific edits to `PROGRESS.md`, but do not apply them yet.

When reviewing content, challenge the plan rather than polishing only the file. A well-formatted plan can still point in the wrong direction.

## Judgement standards

Prioritise by impact:

- **Must address** — plan gaps risking incorrect work, broken verification, misleading commits, data loss, security, accessibility regressions, or blocked handoff
- **Recommended** — changes improving sequencing, scope, tests, docs, maintainability, or developer experience
- **Optional** — broader ideas that could raise quality but shouldn't block current work

Be practical. Prefer small plan edits. Recommend a spec or ADR only when existing plan cannot carry context cleanly and decision is durable, surprising, and trade-off driven.

## Output

Use this shape:

```markdown
## Overall assessment of the project direction

<Is the planned work directionally strong? Name the main reason.>

## Assessment of PROGRESS.md as an execution plan

<Is the file usable for multi-session execution? Mention clarity, sequencing, commit boundaries, and verification.>

## Gaps or issues

- [Impact] <gap or issue, with file/section reference when useful>. Why it matters: <reason>.

## Recommended changes to the plan

- <specific change to an existing section, task, risk, note, expected commit, or verification step>.

## New ideas worth considering

- [Optional/Exploratory/Recommended] <idea and why it may improve the project>.

## Suggested priority order

1. <highest-impact next plan change>
2. <next>

## Specific edits to make to PROGRESS.md

- <concrete edit, insertion, removal, or move>.

## Assumptions, risks, and open questions

- <unknown or assumption that affects confidence, limited to an observed failure or a concrete unresolved scenario traced from changed lines to a real consumer or public contract>.

## Checks run

- `<command>` — <result>.

## Next step

<One concrete action: approve edits, answer an open question, or choose which recommendation to apply first.>
```

If a section has no items, say `None found.` or `None.` Do not omit sections unless the user's requested format differs.

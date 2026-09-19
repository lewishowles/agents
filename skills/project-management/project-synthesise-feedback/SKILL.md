---
name: project-synthesise-feedback
description: >
  Use this skill when asked to review, compare, or combine suggestions from another agent or reviewer. Turn feedback into practical next steps. For direct code or PR review, use code-review.
---
# Project synthesise feedback

Critically combine another agent's suggestions with your own judgement. Produce one stronger recommendation set, not a commentary track on whose answer is better.

Default to analysis and recommendations only; do not edit files unless the user explicitly asks after the synthesis.

## Scope

Use when the user provides advice, a plan, review notes, or implementation suggestions from another agent, reviewer, or prior thread and asks what to keep, change, reject, or add.

Assess practical improvements across the task, plan, implementation, architecture, UX, accessibility, maintainability, testing, performance, developer experience, documentation, security, and long-term quality when relevant.

Broad ideas welcome when they may materially improve the work. Label optional, exploratory, or conditional unless necessary. Don't invent requirements, pad with speculative upgrades, or recommend complexity for its own sake.

## Startup

Read user feedback first. Gather only context needed to judge it:

1. Relevant project instructions and workspace facts
2. `PROGRESS.md` when feedback concerns plan or current work
3. Changed files when feedback concerns uncommitted implementation
4. Source, docs, tests, or generated-file facts referenced

If feedback can be judged from provided text, skip repo inspection. Say what needs checking if evidence is missing; don't guess.

Apply the `code-lookup` routing skill for structural questions. Use targeted reads; avoid generated, vendored, cached, build, dependency, coverage, or binary output.

## Review method

1. Identify the original task or decision feedback responds to
2. Extract concrete claims, recommendations, assumptions, implied priorities
3. Test each against available evidence, project constraints, user goals, proportionality, cost
4. Keep strongest ideas; rewrite into practical recommendations
5. Push back on weak, unsupported, redundant, risky, overbroad, or low-value ideas
6. Add missing ideas that materially improve outcome
7. Scan accepted and rejected ideas for the recurring pattern behind the recommendation
8. Convert synthesis into ordered next steps

Don't treat suggestions as authoritative; don't reject just because from another agent. Goal is best combined result.

## Judgement standards

Prioritise:

- correctness and user intent before polish
- small, high-impact fixes before broad rewrites
- project conventions before novel architecture
- accessibility, security, data safety when relevant
- test and verification gaps hiding regressions
- maintainability and developer experience reducing future cost

Challenge suggestions that:

- depend on unverified assumptions
- expand scope without clear value
- introduce new dependencies, tools, abstractions, process without need
- optimise for theory while delaying delivery
- duplicate existing patterns or planned work
- conflict with instructions, workspace files, or generated-file boundaries

## Output

Use this shape unless the user asks for a different format:

```markdown
## What I agree with and would keep

- <strong idea, with any caveat or refinement>.

## What I would change, remove, or push back on

- <weak or risky idea>. Why: <reason>. Better option: <alternative>.

## Additional ideas to take this further

- [Recommended/Optional/Exploratory] <new idea and why it matters>.

## Specific recommended next steps, ordered by impact

1. <highest-impact action>
2. <next action>

## Risks, assumptions, and open questions

- <risk, assumption, or question that affects confidence, limited to an observed failure or a concrete unresolved scenario traced from changed lines to a real consumer or public contract>.

## Checks run

- `<command>` — <result>.

## Next step

<One concrete action: choose recommendations, approve edits, or answer an open question.>
```

If a section has no items, say `None found.` or `None.` Keep the answer concise enough to act on; do not preserve every suggestion if it does not change the recommendation.

If several suggestions fail for the same reason, group the rejection and name the pattern. Do not pad the answer with every weak idea just to prove it was considered.

## Attribution

The grouped rejection and recurring-pattern guidance adapts ideas from `danium/lateral-thinking`, MIT licensed.

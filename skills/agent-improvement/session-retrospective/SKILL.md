---
name: session-retrospective
description: >
  Use this skill when asked to learn from, retrospect on, review, or extract lessons from a difficult agent session without jumping straight to creating a new skill.
filePatterns: []
pathPatterns: []
---
# Session retrospective

Turn a difficult agent session into a non-blaming learning brief for this agents repo. The failure this skill prevents is overfitting one painful session into an automatic new skill, rule, or process change without checking evidence and existing coverage.

Default to analysis and recommendations only. Do not edit files, log friction, create skills, or amend rules unless the user explicitly asks after the assessment.

## Scope

Use when the user asks to learn from, retrospect on, review, or extract lessons from a specific agent session.

The session evidence may be:

- the current conversation
- a pasted transcript or excerpt
- a user's summary of what went wrong
- a friction note that has not yet become a recurring pattern

Do not use this skill for:

- recurring friction review, use `friction-review`
- external artefacts such as websites, repos, docs, or skill collections, use `project-learn-from-source`
- feedback already written by another agent or reviewer, use `project-synthesise-feedback`
- general repo health checks, use `agent-config-review` for this repo or `project-audit` for other projects
- creating a new skill directly, use `skill-craft` after the retrospective recommends that route

## Startup

Start from user-visible evidence. Don't rely on private reasoning, hidden tool outputs user didn't ask about, or reconstructed context user may not have seen.

When inspecting local session records, aggregate or project the required fields with a script or `jq`. Do not print raw JSONL records, session metadata, or complete transcripts into context. Inspect only the selected events needed to support a finding.

If evidence is thin, ask for smallest useful excerpt:

1. What the user asked for
2. Where the session became difficult
3. Any correction the user gave
4. The final outcome, if any

Then gather only local context needed to judge if issue is already covered:

1. Relevant `rules/` for always-on behaviour
2. Existing skills matching task type or proposed fix
3. `friction-review` output only if user asks to compare recorded patterns
4. Repo scripts or diagnostics only for tooling-coverage lessons

Avoid broad reads. This skill is learning triage, not audit.

## Review method

1. **Describe neutrally** — state what made session difficult without attributing blame or intent
2. **Name the behavioural gap** — identify specific agent behaviour needing change
3. **Separate causes** — distinguish missing guidance, guidance not followed, ambiguous intent, tool limit, tooling gap, unavoidable complexity
4. **Check existing coverage** — decide whether current rules, skills, hooks, diagnostics, docs already address gap
5. **Choose destination** — route each lesson to: no change, friction record, existing rule, existing skill, new skill, script/check, docs, or user preference
6. **Apply evidence bar** — one session justifies a note; new skills need repeated concrete failure
7. **Prefer minimal changes** — recommend smallest amendment preventing or shortening difficulty

## Routing guidance

- **No change** — one-off, already resolved, too ambiguous, or not preventable
- **Friction record** — concrete but needs recurrence evidence before changing rules or skills
- **Existing rule** — behaviour should apply every turn, regardless of task type
- **Existing skill** — task-specific behaviour; skill already exists
- **New skill idea** — specific, repeated failure mode not already covered
- **Script or check** — automation catches issue more reliably than prose
- **Docs or template** — user-facing contract, setup path, or reference missing context
- **User preference** — personal workflow preference, not general agent rule

## Output

Use this shape unless the user asks for a different format:

````markdown
## Session signals

- <Neutral description of what made the session difficult.>

## Lessons

- **<Short lesson>**: <specific behavioural gap or system gap>.
  - Evidence: <user-visible moment or excerpt>
  - Existing coverage: <covered by X, partially covered by Y, or not found>
  - Recommended destination: <no change | friction record | rule | existing skill | new skill idea | script/check | docs/template | user preference>
  - Proposed action: <specific next step, or "watch for recurrence">

## Suggested friction entries

```sh
friction add "<category>" "<detail>"
```

## Proposed guidance changes

```diff
<Only include when evidence is strong enough for a concrete wording change.>
```

## No-change items

- <Issue that should not become repo guidance, with reason.>

## Next step

<One concrete next action for the user.>
````

If a section has no items, write `None.` Keep the brief proportionate to the evidence. Do not invent lessons to fill the template.

## Quality checks

Before responding, verify:

- The brief is non-blaming and describes behaviours, not character or intent.
- Every proposed change names the existing file or skill it would affect.
- New skill recommendations pass the `skill-craft` quality bar: specific failure mode, repeated, and not already covered.
- The output distinguishes "guidance exists but was not followed" from "guidance is missing."
- The next step is a review decision or data-gathering step, not an automatic edit.

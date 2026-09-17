---
# Generated — edit skill.json and SKILL.body.md instead.
name: skill-craft
description: >
  Use this skill when authoring, designing, or evaluating a new skill in this repo. Covers intake → design → build → lightweight eval lifecycle.
do-not-use-when:
  - Updating the content of an existing skill — use the skill directly
  - Authoring rules — those go in src/rules/, not src/skills/
  - General project maintenance — use the project-management skills
---
# Skill-craft

Lifecycle for authoring and evaluating skills in this repo: intake → design → build → eval.

## Quality bar

Apply this before writing anything. A skill earns its context cost only if all three pass:

- **Specific failure mode** — name a concrete example of the model doing this wrong without the skill. "Be thorough" fails this bar; "agent reimplements `clamp()` instead of using the project helper" passes.
- **Repeated** — has appeared more than once across sessions or projects. A single edge case doesn't warrant a skill.
- **Not already covered** — search `skills/` for an existing skill that addresses this domain. Extending an existing skill is almost always better than creating a new one.

If any of the three fails, extend an existing skill or discard the idea.

## Intake

1. Name the failure mode — one sentence: what does the model do wrong today that this skill would correct?
2. Verify it's repeated — more than once, in different sessions or projects.
3. Check for existing coverage — `rg "skills/" -l "<keyword>"` before creating anything new.
4. Define the trigger — what user phrase or task type fires this skill? Specific enough to avoid misfires, broad enough to catch real cases.

## Design

1. **State the contract** — what will an agent reliably do differently after loading this skill? Write as one invariant sentence.
2. **Choose structure** — ordered checklists for workflows; bullets for independent constraints; avoid prose for step-by-step instructions.
3. **Write do-not-use-when** — at least one exclusion. Broad trigger coverage creates false positives.
4. **File-triggered vs. prompt-triggered** — file-triggered loads on every edit of matching types; prompt-triggered loads when phrases appear. File-triggering applies to every edit of those types, not just mentions.
5. **Avoid trigger competition:** reserve broad phrases for router or coordinator skills. Technique or task skills should use specific triggers that do not compete with their router.
6. **Add support material only when it earns its cost:** keep the operational procedure in `SKILL.body.md`; put optional depth in `references/`, a reusable output shape or edge case in `examples/`, and deterministic checks in `scripts/`. A script must test a concrete mechanical contract, run without new dependencies where possible, and include `--selftest` when it has meaningful internal behaviour. Do not add empty directories or boilerplate examples.
7. **Extract mechanical workflow:** when a skill repeatedly dispatches agents, re-evaluates their output, carries intermediate state, or mechanically adjudicates results, move those parts into a deterministic helper, hook, or validation. Keep model calls for judgement. Confirm equivalent black-box behaviour and report unresolved findings rather than treating a budget limit as success.
8. **For conduct-style skills, consider the Intent/Evidence/Decision/Execution/Recovery lens:** what failure this prevents, what evidence triggers it, what's being decided, what the agent should do, and what to do when evidence is missing. Skip for mechanical, step-by-step skills where the lens adds no clarity.

## Build

1. Create `skills/<name>/skill.json` — description under 200 characters; `when` under 100 characters; `promptTriggering: true` unless file-triggered.
2. Create `skills/<name>/SKILL.body.md` — lead with the failure mode the skill corrects; prefer checklists over persona descriptions.
3. Regenerate indexes: `PATH="/opt/homebrew/bin:$PATH" bash scripts/sync.sh </dev/null`.
4. Validate: `PATH="/opt/homebrew/bin:$PATH" bash scripts/validate.sh </dev/null 2>&1 | tail -5`.

## Eval

After writing or materially changing a skill, run these checks without re-reading the skill body:

1. **Recall test** — without re-reading: what does an agent do differently? Vague answer means body is too abstract.
2. **Misfire test** — would the model handle the trigger phrase correctly without this skill? If yes, the skill is likely redundant.
3. **Scope test** — does it cover multiple coherent domains? Each section should be one job. Split if not.
4. **Checklist test** — can any prose instruction paragraph become a numbered list without loss? Checklists are more reliable.
5. **Minimality test** — could the same change be achieved with fewer tokens? Over-specified skills waste context. Permission or instruction often suffices.
6. **Behaviour-trap test** — for high-impact guidance, write one tiny prompt that triggers the failure. Confirm the skill changes the next action, not wording. Keep the prompt and expected next action in `examples/` when the test will be reused; otherwise note why it is not worth keeping.
7. **Honesty test:** where a skill generates options or recommendations, does it say when to reject, group, or stop instead of padding the output?

## Skill vs. rule boundary

If guidance should apply on every turn regardless of task type, it belongs in `rules/global-rules.md`, not a skill. Skills are task-scoped; rules are always-on. When uncertain: if you'd want this applied even when the user hasn't said anything about the topic, it's a rule.

## Attribution

The trigger-competition and honesty-test guidance adapts ideas from `danium/lateral-thinking`, MIT licensed.

The Intent/Evidence/Decision/Execution/Recovery lens adapts the behaviour-spec structure from `braintrustdata/agentbehavior` (agentbehavior.dev), Apache 2.0 licensed.

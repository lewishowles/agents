## Skill use policy

Skills are authoritative when their trigger conditions match. Before coding, editing prose, changing config, or reviewing files, inspect the task and file paths and load every skill the next edit or review needs, always `code-style` plus the language or framework skill for code. Do not wait for explicit slash-command invocation.

Use these routing rules when the task matches them:

- Creating a new component or changing a component's public props, slots, emits, models, or exposed methods → `component-api-design`
- Choosing, reusing, or wrapping an existing `@lewishowles/components` component or API → `component-library`, including when the work is inside the component library repository itself

For all skill use:

- Re-read a skill only if the task type changes, the user asks, or you need a specific detail. Otherwise keep applying the loaded guidance without announcing it.
- Load the smallest matching set; do not speculatively load adjacent skills. For analysis, review, or planning, do not load implementation skills (see Scope default in global-rules).
- Defer a matching skill whose guidance applies to a later part of the task (tests, copy, docs) until work reaches that part.
- Skip a skill's independent lookup for a fact a dispatch packet, handoff, or prior response has already inlined (an API shape, a token list, a routing decision). Load the skill later only if the task needs guidance beyond that inlined fact.
- If a skill's output looks truncated or incomplete, trust it or re-read only the missing range. Do not re-invoke the whole skill to remove the uncertainty.
- Summarise constraints in your own words — do not quote skill sections back.
- If a skill conflicts with the user's token-budget preference, follow the preference and note the tradeoff.
- Two loaded skills disagree? The more specific skill wins for the part it owns. Say which guidance you set aside and why.

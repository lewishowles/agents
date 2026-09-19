---
name: friction-review
description: >
  Use this skill to turn recurring friction patterns from friction summary into specific, minimal, human-reviewed amendments to src/rules/ or src/skills/. Uses friction resolve after an accepted amendment, proposes a diff per pattern, and never auto-applies.
filePatterns: []
pathPatterns: []
---
# Friction review

Turns recurring friction patterns into specific, minimal, human-reviewed amendments to `rules/` or `skills/`. Captured friction with no review step has no payoff, so this workflow closes that gap.

## Workflow

1. **Summarise active friction** — run `friction summary --json` (it reads the shared friction database, so the working directory does not matter). It returns every active friction entry grouped by `category`, `cwd`, and `detail`, with each group's `count`, ordered most frequent first. Do not inspect the database directly.
2. **Take top recurring patterns** — entries with count ≥ 2 warrant review; a single occurrence is usually not yet a pattern. Group entries describing the same failure when their `cwd` or `detail` differs slightly. Treat `check-fail` rows as verification debt unless detail shows repeated agent behaviour that existing guidance would not prevent. Run `friction summary --include-check-fails --json` only when reviewing verification debt. If a previously resolved pattern reappears, say so explicitly; the earlier amendment did not hold, and the proposal should account for why.
3. **Make the tool-error pass** — every review must also run `friction summary --include-tool-errors --json`, which returns tool-error rows mixed in with everything else; run `friction summary --include-tool-errors --category tool-error --json` to see only those rows. Tool-error detail often includes a unique command or exact error, so cluster its results by error-message substring or command shape rather than relying on count alone. Treat each repeating cluster as a pattern from step 2.
4. **Decide the fix's home** — if guidance applies every turn regardless of task, it belongs in `rules/global-rules.md` (mirror in `skills/global-rules/SKILL.body.md`). If task-specific, it belongs in the relevant `skills/<name>/SKILL.body.md`.
5. **Propose a diff** — for each pattern, show exact before/after text change. State which file, why this warrants a rule rather than a one-off fix, and what evidence supports it.
6. **Never auto-apply** — this skill proposes; the user reviews and confirms before any file change. Human review is the write gate.
7. **Record the resolution** — once the user confirms an amendment lands, run `friction resolve <category> <pattern> --reference <ref> --json`, where `ref` is a commit message, PR link, or short description. `<pattern>` must match the group's `detail` string exactly; a paraphrase is accepted but resolves nothing. `friction summary` hides matching events only when their timestamp is at or before the resolution timestamp. Later matching events remain visible, which shows that the earlier amendment did not hold.

## What makes a good amendment

- **Specific** — name the exact behaviour to change, not "be careful"
- **Minimal** — the smallest wording change preventing recurring failures. Don't restructure the section
- **Evidenced** — cite the `friction summary` pattern (category + count), not a hunch
- **Placed correctly** — always-on goes in `rules/`; task-triggered in `skills/`. If both mirror it (like `global-rules.md`), update both in the same proposal

## Skip conditions

- `friction summary` is empty or has no entries with count ≥ 2: report that; don't force a proposal
- Recurring pattern already covered by existing guidance and agent simply didn't follow once: flag as possible one-off, not a guidance gap; suggest logging one more before amending. Stops applying at count ≥ 3: the guidance exists and is still being missed, so ask why rather than dismissing it. Is it ambiguous, scattered across files, or in the wrong place for when it's needed? Propose the fix that answers that; often clarifying or consolidating existing wording, not adding more.

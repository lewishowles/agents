---
name: friction-review
description: >
  Use this skill to turn recurring friction patterns from friction summary into specific, minimal, human-reviewed amendments to src/rules/ or skills/. Uses friction resolve after an accepted amendment, proposes a diff per pattern, and never auto-applies.
---

# Friction review

Turns recurring friction patterns into specific, minimal, human-reviewed amendments to `rules/` or `skills/`. Captured friction with no review step has no payoff, so this workflow closes that gap.

## Workflow

1. **Summarise active friction** — run `friction summary --json` (it reads the shared friction database, so the working directory does not matter). It returns active entries except the automatic `check-fail` and `tool-error` records, most frequent first. Entries with a key are grouped by category and key, even when their details differ; entries without one are grouped by category and exact detail. Each row has a `count`, a `key` (null when the entries have none), an `example` showing the latest detail, and `folders` listing the working directories the entries came from. Do not inspect the database directly.
2. **Take top recurring patterns** — treat any row with a count of 2 or more as a pattern. Also cluster unkeyed rows by the underlying failure and same-key rows across categories; either can reveal repeats across separate rows. Split a group that covers several distinct mistakes until each one could be fixed by one small wording change. To key an unkeyed cluster, get each entry's `id` from `friction list --include-check-fails --include-tool-errors --json`, then draft a JSON mapping of IDs to one key for `friction apply-keys`. Its entries then group and resolve by category and key. Use examples and folders to understand the behaviour, then check whether guidance added since the entries were logged already prevents it. If so, propose resolving it against that change instead of amending again. If a previously resolved pattern reappears, say so explicitly; the earlier amendment did not hold, and the proposal should account for why.
3. **Make the check-fail and tool-error passes** — every review must also run `friction summary --include-check-fails --category check-fail --json` and `friction summary --include-tool-errors --category tool-error --json` as separate queries. Treat `check-fail` rows as verification debt unless the example shows repeated agent behaviour that existing guidance would not prevent. The tool already groups `tool-error` entries without a key by command family and error class (the `command_family` and `error_class` fields), so treat each such row with a count of 2 or more as a pattern from step 2.
4. **Decide the fix's home** — if guidance applies every turn regardless of task, it belongs in `src/rules/global-rules.md`. If task-specific, it belongs in the relevant canonical `skills/<group>/<name>/SKILL.md`.
5. **Propose a diff** — for each pattern, show exact before/after text change. State which file, why this warrants a rule rather than a one-off fix, and what evidence supports it.
6. **Never auto-apply** — this skill proposes; the user reviews and confirms before any file change. Show the drafted key mapping to the user and wait for approval before running `friction apply-keys`. Human review is the write gate.
7. **Record the resolution** — once the user confirms an amendment lands, run `friction resolve <category> --key <key> --reference <ref> --json`, where `ref` is a commit message, PR link, or short description. This resolves every entry with that category and key, in any folder. For a row without a key, pass its `example` as the detail instead: `friction resolve <category> "<example>" --reference <ref> --json`. For an unkeyed `tool-error` row, key its entries as in step 2, then resolve with `--key`. `friction summary` hides matching events only when their timestamp is at or before the resolution timestamp. Later matching events remain visible, which shows that the earlier amendment did not hold.

## What makes a good amendment

- **Specific** — name the exact behaviour to change, not "be careful"
- **Minimal** — the smallest wording change preventing recurring failures. Don't restructure the section
- **Evidenced** — cite each pattern's category, key (or example when unkeyed), and count
- **Placed correctly** — always-on guidance goes in `src/rules/`; task-specific guidance goes in the relevant canonical `skills/` folder

## Skip conditions

- `friction summary` is empty or has no recurring rows or clusters: report that; don't force a proposal
- Recurring pattern already covered by existing guidance and agent simply didn't follow once: flag as possible one-off, not a guidance gap; suggest logging one more before amending. Stops applying at count ≥ 3: the guidance exists and is still being missed, so ask why rather than dismissing it. Is it ambiguous, scattered across files, or in the wrong place for when it's needed? Propose the fix that answers that; often clarifying or consolidating existing wording, not adding more.

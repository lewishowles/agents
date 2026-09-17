---
# Generated — edit skill.json and SKILL.body.md instead.
name: project-review-task
displayName: Project review task
description: >
  Use this skill when assessing a task record or implementation plan before coding, or consolidating independent peer review packets, checking repository truth, scope, evidence, and readiness.
---
# Project review task

Assess a task record or implementation plan before coding so stale repository facts, vague contracts, wrong scope, untestable acceptance criteria, and over-prescriptive recipes are caught while they are cheap to change. Give an evidence-backed `Ready as written` verdict when the task is clear, proportionate, and verifiable; otherwise request only changes that improve evidence, reduce ambiguity or risk, improve maintainability, or make completion more verifiable. Independent review is the default and does not edit the task record or begin implementation.

## Scope

Review planning quality, not an implementation diff, commit range, existing `PROGRESS.md` roadmap, or another agent's feedback. Keep the task's contract separate from implementation mechanics, specialist skill guidance, and delivery coordination.

## Modes

- **Independent review** is the default. Review the task without contacting a planning peer, then write the complete packet to `.agent/reviews/<task-slug>.<model>.md` (see Output). Report a one-line verdict summary and the packet path in chat; `Safe to reset: no` only while the review is in progress, `Safe to reset: yes` once the packet file is written.
- **Consolidation** is available once this model's own packet file exists for the task. Read both models' packet files directly from `.agent/reviews/` — no live contact with the opposite peer is needed. Follow `~/Dev/Configuration/Agents/teams/hcom/roles/planning-peer.md` for the packet-path convention and staleness checks. Do not begin a second independent review, or implement the task.

## Resolve the task

Resolve exactly one task from the `progress` CLI records:

1. Use an explicit task ID from the request or handoff with `progress task get <task-id> --json`.
2. Otherwise run `progress next --json` and use its returned task record.
3. If the request names a task slug or title, match one exact task in `progress task list --json`, then retrieve it with `progress task get <task-id> --json`.

If the supplied ID or name does not resolve, or the lookup is ambiguous, stop and report the task IDs and names returned. Do not choose a fuzzy, partial, newer, or more convenient match.

## Review method

1. Read the resolved task record and current repository guidance. Check `AGENTS.md`, `WORKSPACE.md` when present, `PROGRESS.md` when relevant, and only the source, metadata, docs, or scripts needed to test the task's claims.
2. Record the task ID and `updated_at` value. Re-check the task with `progress task get <task-id> --json` before the verdict; if the record or its `updated_at` value changed during review, stop with a stale-review result.
3. Compare task claims with current repository evidence. Verify named files, commands, generated boundaries, dependencies, existing patterns, and permission or cross-repository limits instead of accepting them from the task alone.
4. Assess the quality rubric below. Mark an item as a finding only when the evidence supports a concrete planning change.
5. Stress the task's boundary and altitude. It must be detailed enough for implementation and verification without prescribing incidental code structure, inventing architecture, or hiding independently reviewable work.
6. Report one verdict. Use `Ready as written` only when no **Must-fix** or **Recommended** finding remains; non-blocking **Nice-to-have** ideas do not prevent readiness.

## Consolidate reviews

1. Retrieve the task record with `progress task get <task-id> --json` and compare its `updated_at` value with the value recorded in your own packet. Do not repeat task-name resolution or reread the task solely for this check. Stop with a stale-state report if the record changed.
2. Compute the opposite model's packet path from the same task slug (see Output) and read it directly. Stop with a missing-packet report if the file does not exist; do not wait, poll, or contact the peer.
3. Verify that the opposite packet's recorded task ID and `updated_at` value match your own packet and the current task record. Stop without editing on any ID or timestamp drift, or if the opposite packet is incomplete.
4. For every finding in both packets, choose `accept`, `combine`, `refine`, or `reject` and state the evidence-based reason and source packet. Preserve a strong task unchanged when no finding justifies an edit.
5. Edit only the resolved task record through supported `progress` CLI commands. Do not edit review packets, planning roles, handoff files, `PROGRESS.md`, or implementation files, and never implement the task during consolidation.
6. Report every decision as a one-line summary and the task edits made (see Output). No message to the opposite peer is needed — consolidation only reads its packet file.

## Quality rubric

- **Repository truth** — named paths, commands, generated outputs, dependencies, and current patterns are real and applicable.
- **Purpose** — the problem, beneficiary, and observable outcome are clear.
- **Clear language** — a reader without the investigation context can understand each requirement; statements name the relevant subject and action, bullets do not compress separate requirements or decisions, unfamiliar terms are explained, and confirmed requirements, recommended defaults, and unresolved questions remain distinct.
- **Behavioural contract** — inputs, outputs, states, boundaries, and relevant failure or recovery behaviour are stated without implementation recipes.
- **Task boundary** — one coherent outcome, explicit non-goals, and independently reviewable files and verification.
- **Chunk review size** — each chunk asks one primary review question and normally touches no more than three substantive files, judged by review effort, not raw file count: a file whose change is only one or two lines does not count toward that ceiling; split independent concerns and dense behaviour slices even when they belong to one feature or file.
- **Dependencies** — real prerequisites, cross-repository relationships, permission limits, and sequencing are named.
- **Altitude** — enough detail to act safely, with no speculative architecture or line-by-line solution disguised as a requirement.
- **Maintainability** — existing helpers and patterns are considered; abstractions, flexibility, and process are proportionate to the evidence.
- **Acceptance and verification** — each load-bearing claim has observable evidence, with static, executed, observed, or blocked checks distinguished where useful.
- **Risks and proportionality** — concrete failure modes, recovery paths, and checks match the task's impact and complexity; every reservation must name an observed failure or a concrete unresolved scenario traced from changed lines to a real consumer or public contract, and must not withhold approval or reduce stated confidence because a linked issue or PR description is absent, untouched behaviour lacks tests, or a future defect is hypothetical.

## Finding standards

- **Must-fix** — stale or false repository facts, missing contract or boundary, unsafe ambiguity, impossible acceptance, missing required verification, or a risk that blocks implementation.
- **Recommended** — a material maintainability, evidence, failure-state, or clarity gap that should be corrected before implementation, including context-dependent shorthand that makes the contract harder to interpret safely.
- **Nice-to-have** — useful polish that is neither required nor a reason to delay the task.

Every finding names the task or evidence location where possible, the problem, its effect, and the smallest planning change that resolves it. Mark assumptions and blocked checks explicitly. If the evidence does not support a change, do not manufacture one.

## Output

Packet files live at `.agent/reviews/<task-slug>.<model>.md`, where `<task-slug>` is the stable slug from the resolved progress task record and `<model>` is `claude` or `codex`. Both models derive this path the same way from the same task record, so no discovery step is needed to find the other's packet.

Write the independent-review packet to that file. Keep empty sections explicit with `None.` or `None found.`:

```markdown
## Task review

- Resolved task ID: `<task-id>`
- Task slug: `<task-slug>`
- Updated at: `<updated_at>`
- Verdict: `Ready as written` | `Changes requested`

## Must-fix findings

- **[M1]** `<path>:<line>` — <problem>. Effect: <impact>. Change: <smallest planning change>.

## Recommended findings

- **[R1]** `<path>:<line>` — <problem>. Effect: <impact>. Change: <smallest planning change>.

## Nice-to-have ideas

- `<optional improvement>`.

## Evidence checked

- **Repository truth** — <paths, commands, or current patterns checked>.
- **Contract and boundary** — <result>.
- **Acceptance and verification** — <result>.

## Assumptions and blocked checks

- <assumption or blocked check, with what would settle it, limited to an observed failure or a concrete unresolved scenario traced from changed lines to a real consumer or public contract>.

## Next step

<If ready, accept the task and begin its approved implementation boundary. If changes are requested, update the task and repeat this review.>
```

After writing the file, report a one-line-per-item summary in chat instead of repeating the packet content:

```text
Reviewed `<task-id>` (`<updated_at>`) → <verdict> — packet: `.agent/reviews/<task-slug>.<model>.md`
- [M1] <one-line summary>
- [R1] <one-line summary>
```

Report consolidation results the same way: one line per finding decision, plus the resolved task and the task edits made. No packet file is written for consolidation itself; the edited task is the deliverable.

```text
Consolidated `<task-id>` (`<updated_at>`) — packets: `.agent/reviews/<task-slug>.claude.md`, `.agent/reviews/<task-slug>.codex.md`
- [M1] <accept|combine|refine|reject> (<own packet|peer packet>) — <one-line reason>
- [R1] <accept|combine|refine|reject> (<own packet|peer packet>) — <one-line reason>
Task edits: `<task-id>` — <what changed through the progress CLI>, or `None.`
```

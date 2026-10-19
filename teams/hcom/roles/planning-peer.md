# Planning workflow for an Orchestrator

Apply these extra instructions alongside `teams/hcom/roles/orchestrator.md`. You hold one model's task-review packet for a cross-model planning exchange. The consolidator owns packet reconciliation and task edits. Your standard tag is `<repo>-plan-<claude|codex>[-<label>]-orchestrator`; your Scout shares that team label.

## Overrides to the standard Orchestrator role

- Write your own `.agent/reviews/` packet instead of routing that file write to an Implementer. During consolidation, edit the task through `progress` yourself. The standard Implementer and Reviewer handoff and review gate do not apply to these planning records.
- Run the review skill's task-resolution and consolidation reads yourself where this workflow explicitly calls for them; route repository research and verification to your team's Scout.
- Report review summaries and checkpoints to the human in normal chat; no Orchestrator sits above you. This workflow does not propose a commit message.
- Skip the chunk proposal and chunk records. The only progress change this workflow makes is the consolidation edit to the task record.

## Hold the independent packet

- Complete the independent task review before consolidating. Do not read the opposite model's packet file during that review, even if it already exists.
- Resolve the task using the review skill's exact-resolution order, then retain its ID, slug, and `updated_at` value.
- Write the complete packet, verdict, every finding and its evidence, and the resolved task ID, slug, and `updated_at` value to `.agent/reviews/<task-slug>.<model>.md` (`claude` or `codex`, matching this peer). Report `Safe to reset: no` only while the review is in progress; once the file is written, `Safe to reset: yes` because the packet no longer depends on this session.
- Do not edit the task record while your own packet is the only one written.

## Delegating to Scout

The Scout is an existing HCOM team member, not a sub-agent you create or spawn. Rules that restrict spawning sub-agents do not prevent this required HCOM routing. In this workflow, “peer” means the opposite planning reviewer, not your own Scout.

```sh
team-send scout --intent request < "$body_file" # Body: Gather these factual receipts: (1) <question or command>; (2) <question or command>. Scope: <paths/area>. Report: <facts for each item>.
```

Report the one-line summary described in the review skill's Output section, then stop. Writing the file is what "delivers" the packet; no further message is needed.

## Locate the peer's packet

Consolidation needs no live contact with the opposite peer. Both packets use the same task slug, so the consolidator finds the other one by reading it directly.

- Compute the opposite model's packet path from the same task slug: `.agent/reviews/<task-slug>.<other-model>.md`.
- Read that file. If it does not exist, stop and report that the opposite review has not been written yet; do not wait, poll, or send an hcom request for it.
- Treat an existing file's content as the packet. No acknowledgement or delivery message from the opposite peer is needed.

## Consolidate and stop safely

Before using the opposite packet, retrieve the task record with `progress task get <task-id> --json` and compare its `updated_at` value with the value recorded in your own packet. Do not repeat task-name resolution or reread the task solely for this check. Compare all of these values:

- The current task ID and `updated_at` value against both packets' recorded values.
- The two packets' recorded task IDs and `updated_at` values against each other.

Stop without editing the task and report a precise stale-state result on any of these conditions:

- The opposite model's packet file does not exist yet.
- The opposite packet is incomplete, or its task ID or `updated_at` value differs from the current task record.
- The current task differs from either packet, or the two packets resolved different task records.

Name the condition, both packet paths, and each observed task ID and `updated_at` value in the stop report. Never consolidate findings from a packet whose task identity or `updated_at` value cannot be verified. When all values match, use the consolidation mode of `project-review-task`, edit only the task record through supported `progress` CLI commands, record the reason for every accept, combine, refine, or reject decision, and do not implement the task.

## Checkpoint

If review or consolidation cannot finish in this session, stop and give one checkpoint.

Use: `PLANNING PEER CHECKPOINT. Safe to reset: <yes|no>. Completed: <review or consolidation state>. Resolved task: <task-id> (<task-slug>, <updated_at>). Packet file: <path, or "not yet written">. Remaining work: <what is left>. Blocker: <precise condition, if any>.`

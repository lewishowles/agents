# Insights review workflow for an Orchestrator

Apply these extra instructions alongside `teams/hcom/roles/orchestrator.md`. You hold one model's independent review packet for a cross-model review of a rendered insights report. The separate Claude consolidator owns packet comparison and recommendation synthesis. Your standard tag is `<repo>-insights-<claude|codex>-orchestrator`; your Scout shares that team label.

## Overrides to the standard Orchestrator role

- Write your own `.agent/reviews/` packet instead of routing that file write to an Implementer. The standard Implementer and Reviewer handoff and review gate do not apply to this independent review workflow.
- Resolve the supplied report and calculate its required hash yourself; route other repository research and verification to your team's Scout. Keep proposal decisions yourself.
- Report review summaries and checkpoints to the human in normal chat; no Orchestrator sits above you. This workflow does not edit progress records or propose a commit message.
- Skip the chunk proposal and chunk records; this workflow produces a review packet, not a chunk of work.

## Hold the independent packet

- Complete the independent report review without reading the opposite model's packet file, even if it already exists, and do not contact the opposite reviewer.
- Use [review insights](../../../skills/agent-improvement/agent-retrospective/references/review-insights.md) to resolve the supplied rendered report path, retain its resolved path and stem, and calculate its exact-byte SHA-256 with `skills/agent-improvement/agent-retrospective/scripts/codex_insights_extract.py`'s existing `hash_bytes` helper.
- Write the complete packet, report evidence, every proposal and its exact before/after diff, the resolved report path, report stem, and SHA-256 to `.agent/reviews/<report-stem>.<model>.md` (`claude` or `codex`, matching this peer).
- Propose only minimal changes under `src/rules/` or `skills/`. State `Never auto-apply` and `User confirmation required before any file change`; do not edit a proposed target.
- Report `Safe to reset: no` until the packet is written and the done message is sent. Then report `Safe to reset: yes`; the packet and message are the durable handoff.
- After writing the packet, send a done message with `team-send reviewer --team insights --intent inform`, giving your model, packet path, report stem, and report SHA-256. Then stop; never consolidate.

## Delegating repository research

Route bounded repository fact gathering to your team's Scout with `team-send scout` instead of contacting the opposite reviewer. Keep the report interpretation, proposal choice, and write gate yourself.

## Checkpoint

If the review cannot finish in this session, stop and give one checkpoint.

Use: `INSIGHTS REVIEW PEER CHECKPOINT. Safe to reset: <yes|no>. Completed: <review state and whether the done message was sent>. Report: <resolved path>. Report stem: <stem>. Report SHA-256: <sha256>. Packet file: <path, or "not yet written">. Remaining work: <what is left>. Blocker: <precise condition, if any>.`

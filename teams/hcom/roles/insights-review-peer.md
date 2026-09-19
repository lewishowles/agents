# Insights review peer

You hold one model's independent review packet for a cross-model review of a rendered insights report. The consolidator owns packet comparison and recommendation synthesis; it does not need to contact the opposite reviewer. Your hcom tag is repository-scoped as `<repo>-insights-review-peer`. Claude review = Opus High; Codex review = gpt-5.6-sol High reasoning.

## Hold the independent packet

- Complete the independent report review before consolidating. Do not read the opposite model's packet file during that review, even if it already exists, and do not contact the opposite reviewer.
- Use `insights-review` to resolve the supplied rendered report path, retain its resolved path and stem, and calculate its exact-byte SHA-256 with `skills/agent-improvement/codex-insights/scripts/codex_insights_extract.py`'s existing `hash_bytes` helper.
- Write the complete packet, report evidence, every proposal and its exact before/after diff, the resolved report path, report stem, and SHA-256 to `.agent/reviews/<report-stem>.<model>.md` (`claude` or `codex`, matching this peer).
- Propose only minimal changes under `src/rules/` or `skills/`. State `Never auto-apply` and `User confirmation required before any file change`; do not edit a proposed target.
- Report `Safe to reset: no` only while the packet is being prepared. Once the packet is written, report `Safe to reset: yes`; the packet is then the durable handoff.

## Delegating repository research

Route bounded repository fact gathering to your own model's Scout instead of contacting the opposite reviewer: `<repo>-scout-claude` when you are the Claude reviewer, or `<repo>-scout-codex` when you are the Codex reviewer. Never send research to the opposite model's Scout. Keep the report interpretation, proposal choice, and write gate yourself.

Before local investigation, identify every factual check needed for the proposal, including the named current rule or skill surface, generated-file boundary, available diagnostics, and relevant existing helper. Send those checks as one bounded Scout packet and wait for the factual receipt before deciding. The Scout returns facts only.

## Locate the opposite packet

The consolidator derives the opposite packet path from the same supplied report stem: `.agent/reviews/<report-stem>.<other-model>.md`.

- Read that path directly only during consolidation. If it does not exist, stop and report that the opposite review has not been written yet; do not wait, poll, or send an hcom request.
- Do not accept a packet path copied from the opposite reviewer. The shared report stem is the identity boundary.

## Consolidate and stop safely

Before using either packet, calculate a fresh current report hash with the same `hash_bytes` helper. Compare all of these values:

- The retained resolved report path and stem against both packet files' recorded values.
- The current on-disk hash against both packet files' recorded hashes.
- The two packet files' recorded paths, stems, hashes, model labels, completion status, evidence, and write-gate statements against each other.

Stop without synthesis and name both packet paths plus every observed path and hash when:

- either packet is missing or incomplete;
- the report cannot be resolved or read;
- a packet's recorded path or stem differs from the retained report identity;
- a packet hash differs from the current report hash; or
- the two packet hashes or report identities differ.

When every value matches, load `project-synthesise-feedback` and give it both packet contents as the feedback to compare. Do not use `project-review-task`'s task-consolidation logic, edit a task, or modify any source file. Synthesis remains a recommendation for human confirmation.

## Checkpoint

If review or synthesis cannot finish in this session, stop and send one checkpoint to the orchestrator. Keep `Safe to reset: no` only if your own packet has not been written; once it exists on disk, checkpointing is safe regardless of session state.

```sh
hcom send @<orchestrator> --intent inform -- 'INSIGHTS REVIEW PEER CHECKPOINT. Safe to reset: <yes|no>. Completed: <review or consolidation state>. Report: <resolved path>. Report stem: <stem>. Report SHA-256: <sha256>. Packet file: <path, or "not yet written">. Remaining work: <what is left>. Blocker: <precise condition, if any>.'
```

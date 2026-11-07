---
name: delegation
description: >
  Use this skill when spawning subagents or using the Agent tool, or reviewing and acting on delegated output or reviewer findings. Covers delegation packets, receipts, independent review, and Claude Code model choices. Do not load for solo work or for reviewing work that no delegate produced.
---

# Delegation

## When to delegate

Delegation is opt-in, not default. Consider it when a plan has 3+ independent tasks that don't share files and the work is well-specified. Do not delegate single-file changes, quick fixes, or tasks with high interdependency — the token overhead of re-reading files outweighs the benefit.

Delegate mechanical work, such as file inventories, structured fact extraction, or log categorisation, only when there are 3+ independent, well-bounded batches. Do not delegate a single known-file read, existence check, or one-off lookup, because dispatch overhead exceeds the saving. Keep task selection, interpretation, change decisions, root-cause analysis, and final verification with the main agent.

The main agent acts as architect and reviewer; subagents act as implementers. Subagent support depends on the agent runtime — if unavailable, fall back to sequential chunked work.

## Delegation packet

Before launching a subagent, state its scope, explicit non-scope, and the evidence or gate that proves the work is done — not just what to build. Name the write scope: the paths the delegate may create or change. A delegate that needs a path outside that scope stops and asks rather than widening it. When the delegated work requires judgement, state why the outcome matters so the delegate can make sound choices beyond mechanical instructions. When the task includes a cohesive subsystem whose ownership is not obvious from its caller, name the owning unit and its public contract. State which state, lifecycle, accessibility, and responsive behaviours it owns, and which remain with the caller. Leave internal implementation choices to the implementer. Known future consumers make this especially important. State the abstraction budget as part of the packet: name any shared or public composable, helper, or file the implementer may create. Absent that, the answer is none. Private functions inside assigned files need no advance permission.

Delegated implementers write the comments and docstrings the project's lint requires, without polishing them, and flag non-obvious rationale in their completion report. The orchestrating model owns the final wording: review every comment in the delegated diff from scratch, keeping the implementer's text only where you would have written it yourself.

## Receipt contract

Delegated agents must return: files touched, tests run, exact blocker encountered, or "no change" if nothing was modified, plus a stopping reason (done, blocked, needs approval, or no further progress possible). Reject any result that omits this.

## HCOM roles

HCOM team rules live in `teams/hcom/roles/team.md`, which each role receives at launch.

## Review gate

When reviewing subagent output, use a fresh agent with no intent framing — describe the current behaviour and what to verify, not what you hoped it would do. For security-sensitive or high-stakes work, require two independent runs to agree before committing. For load-bearing changes, run one pass that checks whether the test or verification would have failed under the old broken behaviour, separate from the general code/architecture pass.

## Resolve reviewer findings

An Orchestrator must not discard a concrete reviewer finding because it is labelled non-blocking, recommended, nice-to-have, or craftsmanship polish. Resolve every actionable finding before presenting the chunk for acceptance: make small, scoped fixes directly; return larger fixes to the Implementer within the same review cycle. If a finding conflicts with the approved scope or another rule, is technically unsound, or needs a user decision, explain that and ask the user instead of silently dropping it. Re-run affected verification and have the resulting change reviewed before calling the chunk ready. Treat reviewer approval as incomplete unless its durable review record contains the craftsmanship inventory required by the review skill. After a wording, naming, value, or structure fix, require a fresh craftsmanship pass over the whole current chunk rather than the fix diff alone.

## In Claude Code

Where the runtime supports forking, prefer it over a fresh agent when the subtask needs the current conversation's context: a fork inherits that context and can reuse the parent's prompt cache when the prefix is byte-identical, the model and effort match, and the cache entry is still live. Reserve fresh dispatch for cases that need genuine independence, as in the Review gate above. Do not claim a cost saving without runtime usage evidence.

In Claude Code, `/advisor` can escalate to Opus for a second opinion mid-session without spawning a full subagent. Use it for planning, synthesis, or final review when the task doesn't warrant full delegation.

Match model capability to the task: Haiku for mechanical extraction, high-volume formatting, file inventories, structured fact extraction, mechanical comparison of identified file sets, and log categorisation. Sonnet is for implementation and focused code changes; Opus is for planning, cross-file synthesis, and final review.

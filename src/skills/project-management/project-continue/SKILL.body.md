# Project continue

Resume from the `progress` CLI records, with optional root-level `PROGRESS.md` freeform prose when present.

## Progress records

The `progress` CLI stores the current project, release, task, chunk, discovery, decision, and handoff records. Run `progress next --json` at startup to identify the active task and chunk. Use `progress context get --json` when the current handoff needs more detail.

`PROGRESS.md`, when present, is optional root-level freeform backlog prose. Do not use it as a fallback for task, chunk, queue, release, discovery, decision, or handoff state. If the `progress` project binding is missing or uninitialised, report the explicit error, inspect `AGENTS.md`, `WORKSPACE.md`, package scripts, and nearby docs for safe local context, and ask the user to initialise or install `progress` before writing progress records. Use the full task and chunk contract returned by `progress next --json`.

## Command syntax

Run `progress commands` once per session to confirm the full command list; run `progress <noun> <action> --help` only when that still leaves a flag unclear. Common commands have stable signatures:

```sh
progress next --json                              # session start: active task + chunk
progress task start <task_id>                     # id is positional
progress task complete <task_id>                  # when no pending or active chunks remain
progress chunk start <chunk_id>
progress chunk complete <chunk_id>
progress discovery add (--release <release_id> | --task <task_id>) '<body>'  # body is positional, not --body
progress decision add (--release <release_id> | --task <task_id>) '<body>'   # body is positional; --supersedes <note_id> optional
progress context get --json
```

`--json` and `--database <path>` are accepted on every command.

**`progress next` selects the current item; it does not validate its scope.** Before resumed or delegated implementation begins, compare the active chunk with its incomplete siblings and stop if it overlaps or subsumes later work.

## Workspace file

Read `<project-root>/WORKSPACE.md` during startup when present. Treat it as factual source for commands, generated files, diagnostics, progress locations, expensive checks, and forbidden operations.

Do not generate a missing workspace file during resume unless the user asks for repo setup. If missing, inspect `AGENTS.md`, package scripts, and nearby docs.

If project guidance conflicts with `WORKSPACE.md`, surface the conflict and trust the workspace file for command safety and generated-file facts. Keep progress state in the CLI records.

When `<project-root>/.agent/scripts/project-diagnostics.py` exists, use `--list` for check discovery and `--check <name>` for verification. Use `--all` only when asked for broad verification.

## HCOM orchestration

When acting as an HCOM Orchestrator, use `hcom list -v` only to identify a same-repository Scout. Send that Scout one bounded request for every factual resume receipt needed, including task or chunk state, outstanding peer reports, and worktree safety. Wait for the Scout's terminal report before deciding and presenting the next task.

Do not inspect source, task state, Git state, peer transcripts, or CLI syntax directly to reconstruct the session. The Scout reports facts; the Orchestrator keeps the decision and human-facing handoff.

On continuation, and before the active chunk is delegated for the first time, obtain `progress chunk list --task <task-id> --json`. An HCOM Orchestrator includes this check in the Scout's bounded resume request instead of running it directly. Review the active chunk and every incomplete sibling using the returned position, title, description, and status. Use `progress chunk get <chunk-id> --json` only when that metadata leaves a boundary vague or suggests an overlap. If the active chunk includes work assigned to a later incomplete sibling, stop before implementation or delegation and narrow or replace it through `project-plan-task`.

## Workflow

1. **Read** — `progress context get --json` first; stop unless the next step is unclear or the task needs deeper context
2. **Compact** — repair stale or missing handoff context; remove duplicate notes and obsolete TODOs; compress completed sub-tasks to one line
3. **Verify** — spot-check recently-completed work landed
4. **Reorient** — confirm active work still fits; move to upcoming if priorities changed
5. **Present** — digest the active task record into the confirmed contract, current repository state, intended files, verification, and unknowns; the user should not need to look up another source. Apply the `project-plan-task` review-size gate to the active chunk. If it exceeds one primary review question or the soft ceiling of three substantive files, propose smaller chunks and wait for confirmation before implementation. Wait for confirmation before editing when the task has material API, behaviour, or interpretation decisions
6. **Complete the chunk plan** — compare the task contract and current discussion with its chunk records. If they reveal additional known chunk boundaries, add or update every known chunk in the same pass before implementation or delegation. Check the split rationale on every pass, not only when the boundaries change: write one if the task has none, and update it when they do. Do not defer a known chunk until dispatch
7. **Continue** — work through the confirmed task; record verified discoveries and decisions with `progress discovery add` and `progress decision add` at handoff. Start with the active chunk returned by `progress next --json`, then use the first incomplete chunk when more remain. Change the chunk to `in-progress` before its first implementation step. When implementation and verification are done, complete the chunk record and present the work for review (changed files, verification, suggested commit message), then stop. Do not wait for the user to accept before completing the record, and do not implement the next chunk in the same pass unless the user asked for all of them
8. **Wrap up** — complete the chunk record as you present it; if it was the last chunk, complete the task and clear the handoff; otherwise refresh the handoff only if a fresh session needs facts the records cannot supply

## Session startup

Read only enough to orient. Stale sessions (5+ min idle) restart from scratch.

- Read the handoff from `progress context get --json`, including `current_goal`, `previous_step`, `next_step`, `standing_context`, `verify_with`, and `stop_marker`
- Verify the active task and chunk records before starting: the CLI status is the source of truth. If the task record says `done` but accepted chunks remain incomplete, complete the chunk records and task through the CLI, then update release and queue state.
- Check the handoff against the active records and worktree before following it. Treat current evidence as fresher. If the handoff's referenced task or chunk shows `done`/`completed` in the CLI records, the handoff is stale: silently prefer `progress next` and proceed, without asking the user to reconcile it. Surface a conflict to the user only when the handoff points at work the CLI still shows active or pending and disagrees with what `progress next` returns.
- Read active task, chunk, discovery, decision, and risk details only when needed
- Read linked feature specs only when active; skip unrelated specs
- Skip completed tasks and old records unless the current task depends on their history
- Run `git status --short` before editing to avoid overwriting work the user has not handled. Do not put its result in `PROGRESS.md`, or use it to infer task completion. Branch creation or switching is not part of task setup unless the user requests it.
- Read `WORKSPACE.md` if present before running local commands
- Surface any open question recorded on a chunk before starting that chunk, and ask it rather than quietly adopting its recommended default
- Verify incomplete tasks and chunks still fit the current scope

## Starting the next task

When user signals readiness ("next please", "let's continue", "what's next") without naming work:

Treat `progress ready` as an ordered queue. When it returns multiple tasks, use the first task. Do not offer the tasks as choices or ask which one to start unless a concrete blocker, dependency conflict, or explicit user request requires reordering.

1. **Name the task** — one sentence: what and where in the plan
2. **Explain why** — one or two sentences: what it unlocks or why it's next
3. **Summarise the contract** — include the task record's public behaviour, files, acceptance criteria, and verification in plain language
4. **Flag unknowns** — name key questions or decisions before starting
5. **Wait for confirmation** — do not start until user agrees (applies at all verbosity levels)

Keep outline short: 3–5 sentences. Give enough context to redirect without a full plan.

Use this flow for any readiness signal that is not resuming an already-active chunk, such as a new session or a mid-session "what's next" after the previous task closed. When an active chunk is already in progress, resume it directly instead of re-presenting the contract.

## Resuming delegated work

If the previous session used subagent delegation:

- Check which delegated tasks were implemented and which still need review
- Unreviewed subagent output needs the review gate (inspect against acceptance criteria) before continuing
- Do not assume subagent output is correct — verify before handing it back to the user
- Do not begin the next implementation chunk in the same pass. Complete the current chunk record, present it, and stop; the next chunk starts in a fresh session
- If delegation is no longer appropriate (remaining tasks are interdependent or small), switch back to sequential chunked work

## During the session

- Keep discoveries and decisions in mind as the session runs; add them with `progress discovery add` / `progress decision add` once at the handoff update, not as separate edits while work is ongoing
- Exception: a durable interruption — material scope change, blocker, or user decision that changes the next session's safe action — is worth recording immediately, since it prevents a future session from repeating costly investigation
- Treat the active task record as a prospective execution contract, not a session log. Change it through the progress CLI only when a material decision changes its outcome, affected files, verification, status, or risk.
- Keep investigation notes, failed attempts, command output, reviewer receipts, and completion recaps out of the task record. Put only the latest result needed to resume in the compact progress handoff; keep durable discoveries and decisions in their CLI records.
- Update "files likely to change" if the scope shifts
- If a task reveals unexpected complexity, add a risk entry before continuing

## Finishing work

Finishing work includes completing the progress CLI records and settling the handoff context. Do not leave either to the next session.

Make one Edit/Write call covering every section below, not a separate call per bullet.

- Keep implementation detail in the progress chunk records.
- When implementation and verification for a chunk are done, complete it with `progress chunk complete <chunk-id>` as you present the work. Do not wait for the user to reply first, and do not treat this as a commit: the diff and suggested commit message still go to the user for review.
- If another chunk remains, refresh the compact handoff with `progress context set` only when a fresh session would otherwise lack something it needs, such as a decision or constraint not already in the chunk contract or the discovery and decision records. If it needs nothing, clear the handoff instead.
- If that was the last chunk and no pending or active chunks remain, complete the task with `progress task complete <task-id>` and clear the stored handoff. A completed task has no next step for `progress context` to hold; `progress next` is the correct source once nothing is active. Update release and queue state through `progress release` and `progress task move` as needed. Do not archive completion in `PROGRESS.md`.
- A whole task finished in one pass with no separate chunks follows the same rule: complete the task and clear the handoff as you present the work.
- If the user comes back with changes, make them in the same session as part of getting that chunk right; do not open a new chunk for routine corrections. Reopen the task only for a genuine change of structure, which is rare.
- When you do refresh the handoff mid-task: set `previous_step` to the last state change and a concise verification outcome; set `next_step` to the first concrete follow-up action; put unresolved facts and constraints in `standing_context`; put any interruption or in-flight command and its known state in `stop_marker`.
- Update release status and queue order through `progress release` and `progress task move` when a release's last task lands as done
- If nothing remains for the current goal, clear the handoff rather than leaving stale TODOs in it
- Compact now if the project keeps root-level `PROGRESS.md` prose and it has grown significantly; current context makes it cheaper

Before settling the handoff, distil what was learned: add verified facts with `progress discovery add (--release <release_id> | --task <task_id>) "<note>"`, choices with `progress decision add (--release <release_id> | --task <task_id>) "<note>"`. Give each note exactly one owner: the release when every task in it shares the fact, otherwise the task. Record failed approaches in the task record or linked spec only when they will help future work. Add only what isn't already captured.

After settling the handoff, do not print or paraphrase its fields. Outside a tool-call checkpoint, present:

1. **What changed** — 1–3 sentences: what was done and what was verified, or skipped and why
2. **Suggested commit message** — the scoped Conventional Commit message as plain text, per global-rules

Then stop. Do not add a next-step section, restate the next chunk or task contract, or ask the user to confirm before continuing. The chunk record is already complete, and a fresh session resumes from `progress next`.

## Wrapping up

- Settle the handoff: clear it on task completion, or refresh it mid-task only with facts a fresh session cannot recover from `progress next` and the records
- Complete chunks and tasks per the flow above as you present them: mark CLI chunks and tasks done, and update release and queue state. Do not recreate an archive section in `PROGRESS.md`.
- If a dead end needs preserving, record one line in the active task record or linked spec: `Approach X failed because Y; don't retry`. Omit it when nothing failed.
- Do not leave the progress CLI records or handoff context half-updated

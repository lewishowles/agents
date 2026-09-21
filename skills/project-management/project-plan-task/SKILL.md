---
name: project-plan-task
description: >
  Use this skill when introducing work into an existing progress CLI plan or splitting a planned task into chunks. Covers placement, releases, tasks, chunks, dependencies, and handoff context.
---
# Project plan task

Add new work to an existing project plan managed by the `progress` CLI. Decide where the work belongs before creating its records, and keep each task reviewable as one coherent outcome.

## Progress CLI

The CLI has these top-level nouns:

- `next`
- `current`
- `project`
- `release`
- `task`
- `chunk`
- `ready`
- `discovery`
- `decision`
- `context`

When the available operation or syntax is unclear, run `progress commands` once before using command-specific help. Use `progress <noun> <action> --help` only when `progress commands` leaves a specific question unanswered. Use JSON output where the command provides it. Do not open `PROGRESS.md` as a substitute for the task, queue, release, or handoff records.

If `progress` is not installed, or the command reports an uninitialised project, inspect `WORKSPACE.md`, `AGENTS.md`, package scripts, and nearby project docs to understand the repository. Do not create a markdown plan or guess a project identity as a fallback. Ask the user to initialise or install `progress` before writing plan records.

Initialise a project only when its identity is confirmed, using the exact project command signature from `progress commands`.

Do not write the progress database directly or use a second task store.

## Workspace file

Use `<project-root>/WORKSPACE.md` when present to choose verification commands, generated outputs, expensive checks, forbidden operations, and repository context.

When `<project-root>/.agent/scripts/project-diagnostics.py` exists, prefer `--check <name>` in verification instructions over raw package scripts. Use `--list` for names; use `--all` only when the section needs broad verification and the user agrees.

Do not generate a missing workspace file. If it is missing, inspect `AGENTS.md`, package scripts, and nearby docs. Mention this command if workspace context would materially improve the plan:

```sh
agents:workspace --write
```

Run it only when the user asks and it exists in the current shell.

## Workflow

1. **Discuss**: identify all known decision-blocking questions about requirements, scope, and dependencies, then ask them together before writing progress records. Do not cap this initial set. Ask further questions only when an answer reveals a material new unknown.
   - For ambiguous or consequential work, group questions by dependency. In each round, ask every question whose prerequisites are settled, give a recommended default, then reassess after the reply. Do not ask downstream questions that assume an answer still open.
2. **Risk triage** (opt-in): identify high-risk files before planning:
   - **Git churn**: `git log --oneline --since="1 month ago" -- <path> | wc -l` means recent change count; high churn can indicate a defect-prone area.
   - **Complexity**: measure large files or high function counts with a targeted symbol or file check.
   - **Fan-in**: use Serena for an exact symbol or codebase-memory for a broad multi-hop impact question.
   - Flag files high on two or more signals in `--risks`.
   - Skip this step for routine, single-file, or familiar work.
3. **Locate**: use the `project`, `task`, and `release` records to identify the current task and the new task's position. Fetch only the selected task record when needed.
4. **Approach exploration** (opt-in): for complex tasks, surface two or three approaches with tradeoffs and wait for the user's choice before writing records. Skip this for single-file, obvious, or already-decided work.
5. **Reorganise**: if the new work changes later dependencies or ordering, update the task dependency and position. Add a release first when the work belongs to a new release.
6. **Insert**: create one task record with the confirmed plan fields. Before adding chunks, run the task-boundary gate's substantive-concern inventory (data and state, interaction and accessibility, presentation states, framework integration, public API, delivery documentation) against this task, and add every chunk that inventory surfaces in the same pass, in decisions-first, mechanical-last order; write the split rationale in that same pass so it cannot be deferred. A task created with a single chunk is a planning defect unless the inventory genuinely found only one reviewable concern; do not defer chunk discovery to the first implementer. Add one chunk per independently reviewable implementation step. Record verified discoveries and decisions in their matching records.
7. **Review checkpoint**: after creating one task, stop for review. Report the task ID, created chunks, verification commands, and suggested commit message without copying the whole record into chat. If the user challenges a record or answers an open decision, fetch only that task record, apply the available CLI change, and wait for approval before implementation. If the CLI cannot represent the requested change, stop and ask instead of editing the database or inventing a parallel file.
8. **Update handoff**: keep the current goal and next action in the `context` record.

## Planning for learning

For non-routine or consequential work, establish only the prompts that apply:

- Problem, beneficiary, and observable success condition
- Assumption with the highest cost if wrong, and the earliest evidence that can test it
- For a deadline, whether date or scope is fixed, plus the first work that may be de-scoped
- Smallest usable end-to-end path, including deliberate manual steps
- For production-affecting work, deployment, observation, support, and reversal needs

Record the resulting durable facts in `discovery` and `decision` records rather than in an unstructured plan file. Attach each one to the release when every task in it shares the fact, and to the task otherwise. When a decision replaces an earlier one, link it as superseding that decision.

End each `decision` body with the condition that would reopen it: a dependency release, a measurement, a product change, or an explicit statement that nothing would. Compaction checks that stated condition to decide whether the entry still earns its place, instead of re-judging every decision from scratch.

## Cross-repo work

When a task may span more than one repository, make the repo boundary explicit before adding the task. This gives us most of the coordination benefit of a synthetic monorepo without requiring a hosted tool or account.

Capture these facts in the task record, its chunks, or a linked spec:

- **Main repo**: where the parent task should run and where most local commands apply
- **Auxiliary repos**: repos needed for read-only context, implementation, generated output, examples, or downstream validation
- **Relationship**: package consumer, API client, generated-output consumer, documentation/example repo, CI dependency, or release baseline
- **Permission boundary**: do not clone, add, edit, push, open PRs, or run remote/networked commands in another repo without explicit user approval
- **Validation owner**: which repo's diagnostics prove the change, including any downstream checks required before release
- **Handoff references**: PR links, task or session IDs, diagnostic log paths, and repo-specific risks

For broad dependency questions, start with local evidence, pick one lookup tool for the question (a code index such as Serena for symbols and callers, a scoped text search for literal strings), and stop once the affected files are known. For the routing table, see `code-lookup`. If the affected repo set is still unclear, record a decision request and ask before expanding the working set.

## Placement principles

- Insert a prerequisite before the task that depends on it by setting `--position` and adding a dependency record.
- Order tasks by dependency, not arrival.
- Treat each active task as an execution boundary.
- Represent independently reviewable implementation steps as chunks under the task.
- After one task, stop for review with the task ID, changed records, verification, and commit message.
- Do not combine release, policy, tooling, documentation, and roadmap work into one task unless they share one reviewable outcome.

### Task-boundary gate

A task owns one coherent feature or outcome and may contain several ordered chunks. Each chunk has one reviewable outcome and focused verification. Create a separate task for independently schedulable feature work, decisions, dependencies, or release boundaries, not merely because the feature needs several implementation steps.

Before creating or delegating a task, confirm it has one coherent change surface and one verification bundle. Several files are fine when they jointly deliver that outcome.

Split the task when it would need separate review decisions for public behaviour, packaging or release work, documentation unrelated to the changed interface, or another independently verifiable outcome. Keep documentation with the interface it explains.

Plan each task around one primary question for the reviewer. Before creating it, inventory its substantive concerns, such as data and state, interaction and accessibility, presentation states, framework integration, public API, and delivery documentation. Treat each as a candidate chunk and combine them only when reviewing one without the other would be misleading. Record why the task is split the way it is in `--split-rationale`. This applies to every task, not only multi-chunk ones: a task with a single chunk has to say why the inventory found only one reviewable concern.

Sibling chunks must not overlap. When splitting a coarse chunk, narrow or replace it so its scope does not subsume the new chunks. Do not leave the original broad chunk active beside the finer review boundaries.

Use three substantive files as a soft ceiling for one task, judged by review effort, not raw file count. A substantive file is one where the changed lines carry logic, tests, or prose the reviewer must actually read; a file whose change is only one or two lines (a registration, an import, a config value) does not count toward the ceiling, because there is nothing there to review. Ten files with one-line changes can be faster to review than one file with a hundred changed lines: weigh the diff, not the file count. Split a dense file across tasks when it contains several behaviour slices. Broad outcomes such as `complete component`, `full public API`, or `all integration` fail this gate unless the underlying change is genuinely small.

An ordered task may use intermediate chunks that are not a complete feature when each is internally consistent, has focused verification, and is not presented or released as complete. Keep the task active until all required chunks are complete.

For a multi-commit task, make each independently reviewable commit a chunk. Complete each chunk record when its implementation and verification are done and you present it, and complete the task after the final chunk. Do not infer completion from Git state.

### Planning-quality gate

Before implementation or delegation, self-check any substantive task against repository truth, contract, boundary, altitude, failure and recovery states, acceptance evidence, and verification. Keep a strong task unchanged; correct only what the evidence supports. Invoke `project-review-task` explicitly for a high-risk or high-ambiguity task, or once a genuine second reviewer is available. A solo run by the same model that wrote the plan does not replace an independent check.

Apply the clear planning language gate from `docs/progress-format.md` to task records, chunks, linked specs, and decisions. Write for a reader who does not share the investigation context: state the problem first, use direct statements with a clear subject and action, keep one requirement, decision, recommendation, or question per entry, explain unfamiliar terms, separate confirmed requirements from recommended defaults and unresolved questions, and make acceptance criteria observable. Preserve exact APIs, paths, commands, edge cases, constraints, failure behaviour, verification requirements, and technical decisions. If clarification would require a new product or architecture decision, record the decision request and ask instead of guessing.

## Feature specs

For larger spikes or ambiguous features, create or reference a per-feature spec under `.agent/specs/` instead of putting design history in task fields or chunks. Keep the task record focused on execution state and add the spec path to the task's `--file` or `--contract-step` value. Do not create specs for small changes, direct bug fixes, routine docs edits, or work fitting one task.

Put planning content that release records can hold in `progress release add` or `progress release edit` and in discoveries and decisions attached with `--release`, not a separate spec file; keep the spec for design detail the records cannot hold. A spec explains why now, the problem, goals, non-goals, approach, entry point and files to inspect, API or schema changes, decisions and open questions, acceptance criteria, risks, and verification. Read or update it only when working on that feature. Full outline lives in the `project-setup` skill's feature-spec section.

## Task records and chunks

Use one `task` record for the work and its stable contract: identity, overview, purpose, contract, split rationale, model tier when needed, files and linked specs, acceptance criteria, verification, risks, release, and position.

The contract is the stable "what": an ordered list of steps, one `--contract-step` each, with the order preserved as given. The steps describe observable outcomes, public behaviour, invariants, constraints, and relevant states, independent of tools. For public, user-visible, or behaviourally significant work, name only the applicable failure and recovery states, such as loading, empty, denied, error, partial, stale, interrupted, or recovery. Keep it observable and invariant-focused, not implementation or testing steps; route accessibility, security, error-handling, and testing mechanics to specialist skills.

Make the final `--contract-step` an explicit out-of-scope statement naming the adjacent work a reader could reasonably assume is included; put release-wide exclusions in the release `--out-of-scope` field. Tasks have no separate non-goals field, and every delegation packet has to state explicit non-scope, so a task without this makes each handoff redraw the boundary from memory. Name a specific exclusion or leave the statement out; a generic "nothing else is in scope" line adds nothing.

Files are a list too. Give each file or spec path its own `--file`, rather than joining several into one value.

On `task edit`, repeating either flag replaces that whole list with the values given, so pass the steps or files you want the task to end up with, not just the new ones. Omitting a flag leaves its list alone. `--clear-files` empties the file list, and there is no matching flag for contract steps, because a task always has at least one.

Use `chunk` records for detailed implementation steps, including decisions-first ordering and mechanical-last work. Work discovered during a chunk stays in that chunk only when it answers the same primary review question. Put cross-cutting or unrelated implementation in its own chunk, or in a separate task when it is independently schedulable. Use `discovery` and `decision` records for durable findings rather than changing the task history by hand.

Once a task's chunk split is known, create or update every known chunk in the same planning pass. Do not keep known chunks only in chat, handoff text, or a spec, and do not wait until implementation or delegation to add them. Later chunks may stay concise until work starts, but each record must name its reviewable outcome and order. Add a chunk later only when its boundary was genuinely unknown earlier.

Start a task when implementation begins. Block it when an external blocker or unresolved decision makes it unsafe to continue, and unblock it only when that condition is resolved. When an unresolved decision affects only some chunks, record the open question and its recommended default in those chunks' descriptions and leave the rest workable; block the whole task only when the answer could change work across all of it. Complete each chunk as you present its finished, verified work. Complete the task after the final chunk, when no pending or active chunks remain. Never infer status from Git state.

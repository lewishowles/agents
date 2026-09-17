# Progress format

Canonical reference for the `progress` CLI data model. The CLI stores project state in SQLite. `PROGRESS.md` is optional freeform prose and is not a task-state store.

## Files

- `~/.agents/progress.db`: the default SQLite database used by `progress`; pass `--database PATH` to use another database
- `<project-root>/PROGRESS.md`: optional freeform backlog prose, such as "Upcoming work" or "Parking lot"; it is not parsed as task, queue, roadmap, note, or handoff state
- `<project-root>/.agent/specs/<feature>.md`: durable feature designs

## CLI data model

The database is scoped to the project bound to the current Git repository. Its data model has seven record types:

| Record      | Role                                                        | State or links                                                                                            |
| ----------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `project`   | Identifies the current repository and project.              | Has a stable ID, slug, and name.                                                                          |
| `release`   | Groups related tasks in roadmap order.                      | `planned`, `active`, or `done`; tasks may refer to it.                                                    |
| `task`      | Stores one reviewable outcome and its planning fields.      | `ready`, `in-progress`, `blocked`, `needs-decision`, or `done`; may have dependencies, chunks, and notes. |
| `chunk`     | Stores one unit of work within a task.                      | `pending`, `active`, `done`, or `skipped`; at most one is active per task.                                |
| `discovery` | Stores a verified finding that helps future work.           | A note belonging to exactly one release or task.                                                          |
| `decision`  | Stores a decision and, when needed, the note it supersedes. | A note belonging to exactly one release or task.                                                          |
| `context`   | Stores the current handoff for one project.                 | One record per project, replaced by `progress context set`.                                               |

Use `progress next`, `progress context get`, and `progress ready` for bounded read surfaces. Use `progress --help`, then `progress <noun> --help`, for the exact command and flag syntax. Use `--json` when another tool or hook needs the stable agent response envelope. The active task is the project's single `in-progress` task. Its active chunk is the next unit of work. `progress next --json` returns that task and chunk; `progress ready --json` lists tasks whose dependencies allow them to start. Task position, release position, dependency edges, and lifecycle status are stored in the database, so no queue table is needed in `PROGRESS.md`.

## Status and completion

The database is the source of truth for task and chunk status. Never infer status from Git state.

An agent completes a chunk or task record when its implementation and verification are done and it presents the work for review. It does not wait for a separate acceptance reply. Presenting is not committing: human review and the commit still follow.

Complete each chunk as you present its finished work. When the last chunk is done and no pending or active chunks remain, complete the task and clear the stored handoff. Update release and queue state through `progress release` and `progress task move`. If the user comes back with changes, make them in the same session as part of getting that chunk right rather than opening a new chunk.

## Clear planning language

Write task records, chunk titles and descriptions, feature specs, and decisions for a reader who does not share the investigation context. Before marking a task `ready`:

- State the concrete problem before the proposed work.
- Use direct statements with a clear subject and action. Where shorthand could be ambiguous, name the actor, input, behaviour, and result.
- Keep one requirement, decision, recommendation, or question per entry.
- Explain unfamiliar terms at first use, while preserving exact API names, paths, commands, standards, and platform terms.
- Keep confirmed requirements, recommended defaults, and unresolved questions visibly separate.
- Describe interactions explicitly, including ordering, filtering, focus, state composition, and failure or recovery behaviour where relevant.
- Write accessibility requirements and acceptance criteria as observable behaviour.
- Preserve edge cases, constraints, failure behaviour, verification requirements, and technical decisions when simplifying the wording.
- Make a task's title and overview and a chunk's title and description readable on their own: state what changed and why in plain words. Keep implementation detail, file paths, technique names, and discovery notes out of them; put those in the chunk body, a `discovery` record, or a `decision` record. For example, write `fix the blank cell for dotted column IDs` / `the cell lookup fails when a column ID contains a dot`, not `treat column IDs as opaque configuration keys and build cells from configured columns`.

If clearer wording would require making a product or architecture decision, leave the requirement unresolved and mark the task `needs-decision` instead of guessing. A rewrite clarifies the existing contract; it does not change scope, behaviour, decisions, or evidence.

## PROGRESS.md

`PROGRESS.md` is optional. Keep it at the project root when a project needs freeform backlog prose, such as an "Upcoming work" or "Parking lot" section. Write and read that prose directly. Do not put task status, active chunk, release roadmap, queue order, discoveries, decisions, or handoff context there; those records belong in the `progress` database.

## Session handoff

The CLI stores one handoff context record per project. It contains `current_goal`, `previous_step`, `next_step`, `standing_context`, `verify_with`, and `stop_marker`. Set it with `progress context set`; read it with `progress context get --json`. The session-start hook reads `progress next --json` for the current task and chunk. Clear the handoff on task completion; refresh it mid-task only with facts a fresh session cannot recover from `progress next` and the records. Do not recreate this context in `PROGRESS.md`.

## Roadmap

Releases are the ordered roadmap, stored in the CLI's `release` records rather than in `PROGRESS.md`. A release has an ID, slug, title, overview, status, position, purpose, risks, and out-of-scope items, shown by `progress release get`. Its status is `planned`, `active`, or `done`; tasks can refer to a release ID. Use `progress release` commands to inspect and change releases instead of maintaining a roadmap table in `PROGRESS.md`.

Use the release for planning facts shared by every task in it, such as its purpose, shared risks, first-version exclusions, and cross-task decisions. Use the task for everything else.

## Tolerance

The CLI database is authoritative for project state. Missing or uninitialised project bindings are reported as explicit errors, so agents can fall back to `WORKSPACE.md`, `AGENTS.md`, package scripts, and nearby docs without guessing. `PROGRESS.md` may be absent because its freeform backlog prose is outside the CLI data model.

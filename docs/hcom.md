# HCOM teams

HCOM lets agents on this machine send messages to each other. A team divides the work between four roles:

| Role         | Responsibility                                                  |
| ------------ | --------------------------------------------------------------- |
| Orchestrator | Plans the work, assigns it, and reports the result to the human |
| Scout        | Checks the repository and runs verification commands            |
| Implementer  | Changes the assigned files                                      |
| Reviewer     | Checks the finished change independently                        |

## Start a team

If you use the `cont` launcher from the Configuration/zsh repository, run `cont` from the project directory to resume the in-progress task from its saved handoff or start the next ready task. Run `cont <task-id>` to choose a task. The launcher starts the four roles in labelled Rex panes, with the orchestrator and implementer above the reviewer and scout. The team works in a separate task checkout under `~/.agents/worktrees/`, where its changes appear.

The launcher and its pane layout live outside this repository. If you don't use it, start each role in its own terminal, read the [role cards](../teams/hcom/roles/), and use `hcom --help` for the available commands.

The orchestrator can read another role's Rex pane to check whether it is idle, stuck, or gone, but it never types into it. When that role owes no report, the orchestrator can run `team-reset <role>` to restart it: after the role says it is safe to reset, after it crashes, or when it is stuck and has not answered one follow-up message. The orchestrator then sends the new session the full assignment through HCOM and tells you which role it reset and why. You still reset the orchestrator and the whole team yourself. If `team-reset` cannot stop the old session, the orchestrator asks you to handle it.

## Pass work between roles

The orchestrator gives each role a bounded assignment. Teammates use `team-send <role> --intent <request-or-inform> --body-file "$body_file"`. `team-send` finds the one live teammate with that role in the current repository and team, and removes the body file once delivery is confirmed, unless it changed after being read. The [shared team rules](../teams/hcom/roles/team.md) give the full sending rules.

The implementer reports changed files and any blocker. The scout reports the commands it ran and their results. The reviewer reports findings on the finished change. Each report includes why the role stopped (done, blocked, needing approval, or unable to make further progress), so the orchestrator knows whether to continue, fix something, or ask you.

When a role has to stop partway, for example at its tool-call limit, it sends a checkpoint instead: the completed work, changed paths, verification results, remaining work, the blocker or decision needed, the exact next action, and whether it's safe to reset. A fresh session can resume from that checkpoint without repeating the work.

---
name: outside-review
description: >
  Use this skill when the human invokes /outside-review to prepare an independent review packet for a progress chunk before commit. Guides the agent through review-packet draft, the review brief, sharing checks, and the human-run build command. Do not use it to mark chunks for review or process reviewer feedback.
disable-model-invocation: true
---

# Outside review

Prepare a review packet for the chunk the human names. The packet should give an outside reviewer the files and context needed to answer the chunk's review question without sharing the full progress export.

## Draft the packet

1. Confirm the chunk ID. Read the chunk with `progress chunk get <chunk-id> --json`, then read its task with `progress task get <task-id> --json`.
2. In an HCOM team, ask the Scout to run `review-packet draft <chunk-id> --json` and report the brief, manifest, and verification paths and the selected files. The draft runs any checks configured in `.review-packet.toml` through `agent-run`. In a solo session, run the draft yourself.
3. Read `REVIEW.md`, `manifest.json`, and `verification.md` at the paths printed by the draft. Check the selected files against the changed work and the review question. The tool includes changed files, direct imports, related tests and configuration, `AGENTS.md`, and READMEs. It lists direct callers for the reviewer but does not add them to the packet.
4. If a direct dependency needed to judge the work is missing, rerun the draft with a repeatable `--include <path>` for each needed file. Use `--base <base>` when the intended comparison base differs from the default. Use `--force` when replacing an existing draft. Do this before writing the judgement sections, because replacing the draft overwrites `REVIEW.md`.

The tool fills the snapshot, comparison base, changed-file list, the reviewed task's overview and done-when, sibling chunk titles and status, dependency titles, file contents, callers, and omissions. Do not add the full `progress export` or repeat those generated sections by hand.

## Complete and check the brief

In an HCOM team, the Orchestrator writes these sections using the team's knowledge and runs the sharing check. In a solo session, the same agent does both:

1. **Main review question:** Check the question prefilled from the chunk's `Outside review:` note, or write it when none was recorded.
2. **Summary without client details:** Summarise the task in terms safe to share with the reviewer.
3. **Known limits:** Name limits that affect the review.
4. **What the reviewer can and cannot verify:** Use `verification.md` to say what the reviewer can verify from the packet and what still needs a local or human check. Do not present an unrun check as evidence.

Read the project's `AGENTS.md` sharing rules and check the finished brief and selected files for client names or other material those rules prohibit sharing. The tool scans for known secrets and local paths, but it does not recognise client terms. Resolve any sharing issue before handing over a build command.

## Hand off the build

Give the human this command to run in the project checkout:

```sh
review-packet build <chunk-id>
```

It writes `~/Downloads/<repo>-review-<chunk-id>.zip` and runs no checks. The build refuses if a selected file changed after the draft; redrafting with `--force` wipes the written sections, so copy them out first. The human runs the build because agents cannot write to Downloads. In an HCOM team, ask the human to send the outside reviewer's feedback back to the same team before the chunk is committed.

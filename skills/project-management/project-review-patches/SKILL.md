---
name: project-review-patches
description: >
  Use this skill only when explicitly reviewing current uncommitted work as separate, refreshable proposed commit patches. The coordinator chooses whole-file or whole-hunk boundaries; a named HCOM Scout creates and checks ignored patch artefacts without changing source, the worktree, or the index.
disable-model-invocation: true
---
# Project review patches

Review current uncommitted work as separate proposed commits. The coordinator decides the proposals and whole-file or whole-hunk boundaries. A named HCOM Scout runs the deterministic helper to write ignored patch artefacts, but does not choose groupings, edit source, stage, commit, or change the index.

## Scope

Use this skill only for an explicit patch-by-patch review request. It covers:

- tracked, staged, unstaged, deleted, and untracked work
- one valid Git patch per proposed commit with 10 context lines, full Git metadata, and content hashes
- complete, non-overlapping whole-file or whole-hunk boundaries
- stale-patch detection and refresh after feedback
- the existing-index decision gate before any proposal is staged

Keep `project-review-worktree` for a normal uncommitted-work review and `project-review-commits` for committed ranges. Do not change either skill as part of this workflow.

## Startup

Read, in order:

1. `<project-root>/AGENTS.md`
2. `agent-run list --json`
3. `PROGRESS.md`, when present, for recent context
4. `git status --short`

Use agent-run for registered checks it exposes. Keep browser checks human-run. Confirm that `.agent/review-patches/` is ignored before asking Scout to write artefacts.

## Boundaries and staged work

The coordinating agent owns the review plan. It must:

1. analyse the complete current worktree, including staged and untracked changes
2. group complete Git hunks into proposed commits without splitting a hunk
3. assign every changed file or hunk to exactly one proposal
4. stop for a human decision when the index already contains staged content

The helper refuses a dirty index by default. Use `--staged-policy include` only after the human explicitly decides that existing staged content belongs in this review. Do not silently mix staged content into a proposal.

The plan is JSON with this shape:

```json
{
	"proposals": [
		{
			"id": "patch-1",
			"title": "Describe the proposed commit",
			"changes": [
				{"path": "src/first-file.py"},
				{"path": "src/second-file.py", "hunks": [0]}
			]
		}
	]
}
```

Omit `hunks` for a whole-file change. The helper rejects duplicate or missing units, partial-hunk boundaries, paths outside the current change set, and unsupported partial binary or mode-only changes.

## Scout artefacts

Send one explicitly named Scout the coordinator-approved plan and the exact helper command. The Scout may run only the skill-owned helper and write its output under the ignored `.agent/review-patches/` directory. The helper writes one `<proposal-id>.patch`, one matching `<proposal-id>.json` metadata file, and a `manifest.json` index. Metadata records the selected paths and hunks, base revision, context size, input hashes, patch hash, and apply-check result.

Create the initial set with:

```sh
python3 skills/project-management/project-review-patches/scripts/create_review_patches.py \
	--plan .agent/review-patches/plan.json
```

Check freshness before showing a patch again:

```sh
python3 skills/project-management/project-review-patches/scripts/create_review_patches.py \
	--check .agent/review-patches
```

Feedback changes only the selected proposal. Update the plan, then ask the same named Scout to refresh it. Regenerate all proposals that share changed inputs before showing them again, and refuse to show or stage a stale patch.

## Review and approval gates

Review one patch at a time. For each proposal, show its purpose, files, hunk boundaries, patch hash, freshness result, and focused checks. Never stage or commit while reviewing.

After review, the human must say exactly:

```text
Patch X approved. Stage it.
```

Immediately before staging, run the helper freshness check. It reports input and patch-hash drift; use Git separately if you need to check how the patch applies to the intended index. Stage only that exact fresh patch. Then show the staged files and one exact Conventional Commit message.

The human must separately say:

```text
Commit patch X.
```

That second phrase authorises the commit only. Neither phrase authorises another proposal, and no inferred approval is valid.

## Output

Report:

- the proposed patches and their coordinator-owned boundaries
- staged-content decisions and any excluded work
- each patch and metadata path, hash, freshness result, and apply check
- feedback refreshes and the proposals affected by them
- checks run, with blocked browser or HCOM evidence called out

Do not report a patch as ready when its inputs changed, its hash no longer matches, its apply check fails, or its grouping overlaps another proposal.

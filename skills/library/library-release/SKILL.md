---
name: library-release
description: >
  Use this skill when preparing to release a supported @lewishowles library package.
filePatterns: []
pathPatterns: []
---
# Library release

Conservative release guardrails for `@lewishowles/components`, `@lewishowles/helpers`, `@lewishowles/testing`, `@lewishowles/cli-style`, `@lewishowles/lint-config`, and `@lewishowles/pkg-checks`. Inspect current repo process first; require explicit approval for irreversible steps.

## Release stance

- Release the smallest coherent change set
- Decide semver from user-facing impact, not code volume
- Use existing package scripts and docs; don't invent tooling unless asked
- Keep publish, tag, push, and registry actions as explicit confirmation points
- Record release rough edges instead of baking in workarounds

## Step 1 — identify the package

Confirm which package is being released:

- `@lewishowles/components`
- `@lewishowles/helpers`
- `@lewishowles/testing`
- `@lewishowles/cli-style`
- `@lewishowles/lint-config`
- `@lewishowles/pkg-checks`

Read package root instructions, workspace file if present, `package.json`, changelog, and release notes before recommending commands.

## Step 2 — classify the release

Choose version bump from observable consumer impact:

| Bump  | Use when                                                                                                 |
| ----- | -------------------------------------------------------------------------------------------------------- |
| Patch | Bug fixes, docs fixes, internal changes, or compatible polish                                            |
| Minor | New exports, components, helpers, props, slots, options, or compatible behaviour                         |
| Major | Removed or renamed APIs, changed defaults, incompatible behaviour, or migration-required styling changes |

When unsure between bumps, name uncertainty and ask before editing version files.

## Step 3 — prepare notes

Write changelog and release notes before publishing. Include only externally relevant changes:

- Breaking changes and migration notes
- New APIs, components, helpers, props, slots, options
- Fixes users may notice
- Deprecations and follow-up timing

Don't include internal refactors unless they explain consumer-visible behaviour.

## Step 4 — verify locally

Use package's existing scripts and documented release checks. Prefer scoped checks; ask before broad, slow, networked, or destructive commands.

Minimum verification to look for:

- Typecheck or build command
- Unit test command if present
- Package or export validation if present
- Generated docs or build output freshness if the package publishes generated assets

If useful check is missing, mention gap rather than inventing release blocker.

## Step 5 — validate likely consumers

For releases affecting consumers, test at least one realistic downstream path before publishing. This applies when the release changes public APIs, exports, CLI behaviour, generated output, styling contracts, package metadata, or documented setup.

Use local process first:

- Identify known consumers from package metadata, import searches, repo docs, boilerplate baselines, user-provided lists
- Include `~/Dev/Repositories/Packages/boilerplate` when change affects future scaffolding or shared defaults
- Use package dry-run or pack commands when supported
- Install unpublished packages into consumer repos only after explicit user approval
- Run consumer repo's documented diagnostics, preferring diagnostics wrapper when present
- Record which consumers checked and which skipped, with reason

Skip this step for docs-only, metadata-only, or internal patch releases unless plausible consumer impact exists. If no consumer can be checked locally, report that gap before publishing; local package tests don't prove release completeness.

## Step 6 — inspect publish contents

Before publishing, confirm package contents and metadata:

- Version and package name
- Entry points and export map
- Files included in the package
- Changelog or release notes
- README or docs affected by the release

Use dry-run/pack commands when available, after confirming package tooling.

## Step 7 — explicit release actions

These packages publish to the npm registry for the next version. Treat `npm publish` or any CI workflow that publishes to npm as the publish step. Do not use GitHub Packages as the target registry.

Stop for confirmation before each irreversible/history-changing action:

- Version file edits if not already approved
- Git tag creation
- Git push if the package workflow publishes to npm from CI
- `npm publish` if the package release process publishes manually
- GitHub release creation

Show exact command and expected effect before asking.

## Step 8 — after release

Report:

- Package and version released
- Verification run
- Downstream consumers checked or explicitly skipped
- Publish, tag, release status
- Any release-process rough edges worth fixing

Don't update consuming projects unless user asks; use `library-update` for follow-up.

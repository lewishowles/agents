---
name: library-update
description: >
  Use this skill to survey supported @lewishowles library releases in a project, or to audit one library for new APIs, fixes, and every place the project could adopt them.
---
# Library update

Find the improvements a shared-library release offers and where the project can use them.

## Invocation

```
/library-update              quick survey of libraries present in package.json
/library-update components   deep audit of @lewishowles/components
/library-update helpers      deep audit of @lewishowles/helpers
/library-update testing      deep audit of @lewishowles/testing
/library-update cli-style    deep audit of @lewishowles/cli-style
/library-update lint-config  deep audit of @lewishowles/lint-config
/library-update pkg-checks   deep audit of @lewishowles/pkg-checks
```

## Step 1: choose the scope

With no argument, survey the libraries in `package.json` dependencies and devDependencies. With a library name such as `components`, run the full audit below for that library.

Supported libraries:

- `@lewishowles/components`
- `@lewishowles/helpers`
- `@lewishowles/testing`
- `@lewishowles/cli-style`
- `@lewishowles/lint-config`
- `@lewishowles/pkg-checks`

If a survey finds no known libraries, say so. A survey also names, in one line each, absent libraries whose features the project appears to duplicate.

In a deep run, if the named library is absent, check whether project code or generators contain work it could replace. Report adoption separately from version updates. Stop only when the library is absent and no adoption opportunity applies.

## Step 2: compare versions

For each library in scope:

1. Read `package.json` to find the declared version constraint
2. Find the exact resolved version from lockfile:
   - `bun.lock` or `bun.lockb`: search for the package entry
3. Use resolved version (e.g. `2.2.1`) as **installed version**

Use the npm registry as the source of truth for published versions:

```bash
npm view @lewishowles/components version versions time --json
npm view @lewishowles/helpers version versions time --json
npm view @lewishowles/testing version versions time --json
npm view @lewishowles/cli-style version versions time --json
npm view @lewishowles/lint-config version versions time --json
npm view @lewishowles/pkg-checks version versions time --json
```

Confirm before running npm registry commands if network access has not already been approved. Identify the latest stable published version from `version` or the `latest` dist-tag. Versions follow the format `X.Y.Z`.

In a survey, use step 3's npm metadata to skim only the releases since the installed version, then check relevant project usage. Report installed versus latest, breaking changes that affect the project, and one line on adoption work from those releases. Recommend a separate single-library run for each with adoption work, and recommend a deep run to find unused current features even when a library is up to date. Keep the survey brief; the remaining steps describe a deep run.

In a deep run, an installed version equal to latest does not end the audit.

## Step 3: inspect releases and current APIs

Use npm package metadata and contents before GitHub. In every deep run, compare the latest version's full API with project usage. Inspect releases between installed and latest, in ascending order, for breaking changes, bug fixes, and deprecations. When installed equals latest, check relevant fixes and deprecations in the current version:

```bash
npm view @lewishowles/components@X.Y.Z description homepage repository readme --json
npm pack @lewishowles/components@X.Y.Z --dry-run
```

If npm metadata or package contents include release notes, changelog entries, or README sections, collect those. If insufficient, ask the user for release notes excerpt instead of GitHub releases or GitHub Packages.

Identify:

- **Breaking changes** — API removals, renamed props, changed defaults, removed exports
- **New APIs** — components, props, helpers, composables, and utilities that could improve the project, even where no local equivalent exists
- **Bug fixes** — particularly for patterns the project already uses
- **Deprecations** — things still working but flagged for removal

For `@lewishowles/components`, use `npx @lewishowles/components@<latest> list` and `npx @lewishowles/components@<latest> info <component>` to compare the latest API with project usage. The npm confirmation rule above applies. Follow the component-library skill for CLI details. For helpers, which has no consumer CLI, use the latest version's README and exports.

## Step 4: hunt through actual usage

Scan project source and project-owned Boilersuit generators when present. Also scan the locations where the named library is actually used: test files and test setup for testing, ESLint and other config files for lint-config, `package.json` scripts for pkg-checks, and scripts or CLI entry points for cli-style. Generators are starting points for future files, so include their stale usage and boilerplate.

For each relevant new feature, look for places it would improve accessibility, simplify markup, remove boilerplate, or remove a workaround, even if there is no local equivalent. For each relevant bug fix, search for local workarounds it makes removable. Check imports, component names, props, slots, and changed patterns in the locations where they occur. Keep searches scoped to existing directories and files.

## Step 5: compare the boilerplate baseline

Check `~/Dev/Repositories/Packages/boilerplate` after the current project scan. It's a baseline for future projects, not an automated oracle.

If the repo exists and is readable, inspect relevant package files, source templates, and `.boilersuit/generators/` files for the same patterns and adoption opportunities. Report improvements separately from the current project so the user can decide whether to update boilerplate in another chunk.

Don't claim boilerplate is "up to date" from version checks alone. At most, say which files or patterns were checked and whether current release notes suggested any concrete changes.

## Step 6: report findings

Structure the output as follows:

### `@lewishowles/<library>`: vX.Y.Z → vA.B.C

For an up-to-date deep run, show the same version on both sides and say that you audited unused current features.

#### Must update

Breaking changes affecting project code. Include path and needed change.

#### Adopt now

Every applicable new API, prop, component, helper, utility, migration from a used deprecated API, and removable bug-fix workaround. Include affected paths and the improvement, even when nothing local is being replaced. Say whether each item fits the dependency-update chunk or a follow-up adoption chunk.

Adopt by default for every library. Defer only when a change alters product behaviour or needs design or product judgement. State that reason for each deferred item.

#### Consider later

Only deferred applicable improvements, each with its reason.

#### Good to know

Fixes and deprecations with no project action after the workaround and usage search.

#### Boilerplate baseline

Concrete changes to consider in `~/Dev/Repositories/Packages/boilerplate`, including `.boilersuit/generators/` paths. Say "not checked" only if repo was missing or unreadable.

#### Not relevant

Omit this section; only report what applies.

---

Keep the deep report concrete: file, import, component, specific change. A survey uses the absent-library line from step 1 and the short version comparison and adoption note from step 2.

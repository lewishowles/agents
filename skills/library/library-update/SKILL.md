---
name: library-update
description: >
  Use this skill to check supported @lewishowles project dependencies for newer releases, review release notes, and identify updates or APIs to adopt.
filePatterns: []
pathPatterns: []
---
# Library update check

Check Lewis shared libraries for new releases, surface changes, and identify updates needed.

## Invocation

```
/library-update              check libraries present in package.json
/library-update components   check @lewishowles/components only
/library-update helpers      check @lewishowles/helpers only
/library-update testing      check @lewishowles/testing only
/library-update cli-style    check @lewishowles/cli-style only
/library-update lint-config  check @lewishowles/lint-config only
/library-update pkg-checks   check @lewishowles/pkg-checks only
```

## Step 1 — determine which libraries to check

If argument given, use it. Otherwise read `package.json` and check dependencies and devDependencies:

- `@lewishowles/components`
- `@lewishowles/helpers`
- `@lewishowles/testing`
- `@lewishowles/cli-style`
- `@lewishowles/lint-config`
- `@lewishowles/pkg-checks`

If a known library is not present, check whether the project or generators contain boilerplate the library replaces. Report missing-library adoption separately from version updates. For example, a project without `@lewishowles/testing` might still need it if test setup or Boilersuit templates duplicate utilities it provides.

If no known libraries are present and no adoption opportunity applies, stop and say so.

## Step 2 — find the installed version

For each library in scope:

1. Read `package.json` to find the declared version constraint
2. Find the exact resolved version from lockfile:
   - `bun.lock` or `bun.lockb`: search for the package entry
3. Use resolved version (e.g. `2.2.1`) as **installed version**

## Step 3 — find the latest release

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

If installed version matches latest release, report up to date and stop.

## Step 4 — fetch release notes for all versions between installed and latest

Use npm package metadata and contents before GitHub. For each newer version, ascending:

```bash
npm view @lewishowles/components@X.Y.Z description homepage repository readme --json
npm pack @lewishowles/components@X.Y.Z --dry-run
```

If npm metadata or package contents include release notes, changelog entries, or README sections, collect those. If insufficient, ask the user for release notes excerpt instead of GitHub releases or GitHub Packages.

Identify:

- **Breaking changes** — API removals, renamed props, changed defaults, removed exports
- **Adoption opportunities** — helpers, components, composables, test utilities replacing boilerplate or simplifying existing code
- **New components or composables** — things the project might benefit from where no equivalent exists
- **Bug fixes** — particularly for patterns the project already uses
- **Deprecations** — things still working but flagged for removal

## Step 5 — scan the project and generators

Scan project source (`src/`) and project-owned Boilersuit generators (`.boilersuit/generators/`) when present. Generators are starting points for future files, so treat stale imports, props, helper usage, and boilerplate there as adoption work even when current project output is up to date.

Focus on:

- Imports from `@lewishowles/components` or `@lewishowles/helpers`
- Imports from `@lewishowles/testing`, `@lewishowles/cli-style`, `@lewishowles/lint-config`, or `@lewishowles/pkg-checks`
- Component names, prop names, composable names, slot names in release notes
- Patterns release notes flag as changed or removed
- Local helpers, repeated boilerplate, custom test setup, CLI styling code, or templates a newer shared library replaces

Use `rg` scoped to `src/` and `.boilersuit/generators/`:

```bash
rg "@lewishowles/components" src/ --files-with-matches
rg "@lewishowles/components" .boilersuit/generators/ --files-with-matches
rg "ComponentName" src/ -l   # repeat per affected component
```

## Step 6 — compare the boilerplate baseline

Check `~/Dev/Repositories/Packages/boilerplate` after the current project scan. It's a baseline for future projects, not an automated oracle.

If the repo exists and is readable, inspect relevant package files, source templates, and `.boilersuit/generators/` files for the same patterns and adoption opportunities. Report improvements separately from the current project so the user can decide whether to update boilerplate in another chunk.

Don't claim boilerplate is "up to date" from version checks alone. At most, say which files or patterns were checked and whether current release notes suggested any concrete changes.

## Step 7 — report findings

Structure the output as follows:

### `@lewishowles/<library>`: vX.Y.Z → vA.B.C

#### Must update

Breaking changes affecting project code. Include path and needed change.

#### Adopt now

New shared-library APIs replacing existing code, reducing boilerplate, or making current usage more direct. Include all affected paths and say whether adoption belongs in the same dependency-update chunk or should split because it touches many files.

Treat `@lewishowles/helpers` simplifications as adoption work by default, even with broad mechanical edits. Defer only when adoption changes product behaviour, needs design or product judgement, or deserves separate review.

#### Consider later

New features/components relevant to the project with no existing local equivalent to replace.

#### Good to know

Fixes and deprecations worth knowing, no immediate action.

#### Boilerplate baseline

Concrete changes to consider in `~/Dev/Repositories/Packages/boilerplate`, including `.boilersuit/generators/` paths. Say "not checked" only if repo was missing or unreadable.

#### Not relevant

Omit this section; only report what applies.

---

If multiple libraries in scope, report separately. Keep concrete: file, import, component, specific change.

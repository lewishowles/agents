---
name: boilersuit
description: >
  Use this skill when consuming an existing Boilersuit generator to create repeatable project files. Covers inspecting project support, listing and describing generators, previewing the complete planned file set, handling existing destinations, and generating only after preview.
---
# Boilersuit

Use existing Boilersuit generators for repeatable structures, not one-off files. Use `boilersuit-generator-authoring` for creating/changing generators. Generators are project-agnostic; follow selected project conventions; don't assume Vue, JavaScript, `src/components`, or `NAME` unless generator establishes them.

## First checks

Confirm CLI exists:

```bash
command -v boilersuit
```

From project folder:

```bash
boilersuit project inspect --json
boilersuit generators list --json
```

If LLVM Profile Error appears, rerun with profile output in `/tmp`:

```bash
env LLVM_PROFILE_FILE=/tmp/boilersuit-%p.profraw boilersuit project inspect --json
```

## Automation contract

Treat installed `boilersuit` CLI as agent automation contract. Prefer its JSON commands over recreating discovery, field requirements, path resolution, collision handling, or project-opening. Use `boilersuit --help` and command help as source of truth.

## Command forms

`<project-path>` optional; omitted means current directory.

```bash
boilersuit project inspect [<project-path>] --json
boilersuit generators list [<project-path>] --json
boilersuit generators describe [<project-path>] <generator-id> --json
boilersuit generators doctor [<project-path>] [<generator-id>] --json [--field TOKEN=value] [--variant id]
boilersuit generate preview [<project-path>] <generator-id> --json [--field TOKEN=value] [--variant id] [--path path] [--skip-existing]
boilersuit generate [<project-path>] <generator-id> --field TOKEN=value --json [--variant id] [--path path] [--skip-existing]
boilersuit project open [<project-path>] (--editor | --terminal | --file-manager) --json
```

Opening editor, terminal, or file manager may need sandbox approval.

## Run profiles

Separate from file generation. Live in `.boilersuit/run.json` (explicit) or inferred from `package.json` scripts; explicit takes precedence. Don't edit/run profiles as side effect of generator consumption. Treat profile changes as separate requested work.

## Generator path model

- `default_path`: base output directory, not token-rendered.
- `files[].output_path`: renders field tokens, may include directories.
- No directory in `output_path` → writes to `<default_path>/<NAME | kebab>/`.
- Directory in `output_path` → owns subdirectories; Boilersuit doesn't add name folder.
- Flat files under tokenised directory: set `default_path=""`, full path in `output_path` (e.g. `lib/{{ CATEGORY }}/{{ NAME | kebab }}.js`).
- Use `--path` to override/prefix base; always preview (explicit `output_path` directories can change final path).
- CLI uses complete visible file set. Variants define alternatives; per-template selection unsupported.

## Generation workflow

1. Run `boilersuit project inspect --json`.
2. Run `boilersuit generators list --json`.
3. Stop if `has_generator_directory` is false or list is empty.
4. Pick matching ID from list; don't invent.
5. Describe it: `boilersuit generators describe "<generator-id>" --json`
6. Map required fields. Ask for missing values if unsafe to infer.
7. Run doctor: `boilersuit generators doctor "<generator-id>" --json --field NAME=<name>`. Resolve errors; review warnings; supply deferred-check values.
8. Preview: `boilersuit generate preview "<generator-id>" --json --field NAME=<name>`.
9. Review every file action and path. `create` writes; `skip_existing` only returned when requested. Don't read full content by default.
10. Read content only when path/action risky, generator unfamiliar, or user asks.
11. Generate only after confirming files match task: `boilersuit generate "<generator-id>" --json --field NAME=<name>`.

Use extra flags only when description/user requires. Use `--skip-existing` only when destinations should stay unchanged and preview lists every skip. Field tokens: SCREAMING_SNAKE_CASE, digits allowed after first char (e.g. `API_V2_NAME`, `WCAG_22_LEVEL`). Read generator description rather than rejecting such tokens.

## Guardrails

- Prefer Boilersuit when requested file matches existing generator.
- Don't use Boilersuit for one-off files faster to write directly.
- Don't run `generate` before `generate preview`.
- Don't use removed `--file` or invent per-template selection.
- Treat preview as plan check, not content review.
- Existing destinations fail safely. Don't use `--skip-existing` unless partial result expected.
- Keep broad reading until after `project inspect` and `generators list`.
- Report when no generator fits; don't force partial match.

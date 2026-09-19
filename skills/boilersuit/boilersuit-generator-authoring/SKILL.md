---
name: boilersuit-generator-authoring
description: >
  Use this skill when creating or editing a project-owned Boilersuit generator under .boilersuit/generators/. Uses the installed CLI contract as the source of truth, plans the generator before writing, runs doctor before preview, and avoids copying schema details that can drift.
filePatterns: []
pathPatterns: [".boilersuit/generators/**"]
---
# Boilersuit generator authoring

Create or edit generators using the installed Boilersuit CLI as contract. Do not rely on remembered field types, filters, schema properties, or path behaviour.

Generators are project-agnostic. Follow target project conventions; don't assume Vue, JavaScript, `src/components`, or `NAME` field unless required.

## Prerequisites

Confirm the CLI and authoring commands are available:

```bash
command -v boilersuit
boilersuit generators contract --help
boilersuit generators doctor --help
```

If unavailable, stop and report CLI needs update. Don't reconstruct schema from this skill.

If a command prints `LLVM Profile Error: Failed to write file "default.profraw"`, rerun it with:

```bash
env LLVM_PROFILE_FILE=/tmp/boilersuit-%p.profraw boilersuit <arguments>
```

## Source of truth

Load the current contract before planning or editing:

```bash
boilersuit generators contract --json
```

Use its structured output for:

- Supported schema versions and properties
- Required and optional fields
- Field types, defaults, validation, and select options
- File conditions and variants
- Placeholder, alias, conditional, and filter syntax
- Output-path behaviour and limitations
- Valid basic and advanced examples

Current implementation: `pascal`, `kebab`, `camel`, `snake`, `constant`, `upper`, `lower`. Verify against loaded contract; CLI wins if they differ (report mismatch).

Tokens: SCREAMING_SNAKE_CASE, digits allowed after first char (e.g. `API_V2_NAME`, `WCAG_22_LEVEL`). Verify `token_format` in loaded contract.

Don't copy contract details into this skill or assume prior projects match current contract.

## Project contract boundaries

Treat installed `boilersuit` CLI as agent automation contract: discovery, validation, preview, path resolution, collision handling, generation. Use command help for unclear options.

Run profiles: separate project capability. Live in `.boilersuit/run.json` (explicit) or inferred from `package.json` scripts. Explicit takes precedence. Don't change profiles as side effect of authoring. Plan profile changes separately if needed.

## Authoring workflow

### 1. Inspect target project

```bash
boilersuit project inspect --json
boilersuit generators list --json
```

Generator files live under:

```text
.boilersuit/generators/<generator-id>/
├── generator.json
└── native template files
```

Template files keep normal extensions; no `.tpl` suffix.

### 2. Design before writing

Present proposal for review:

- Generator ID, display name, purpose, default path
- Fields and why needed
- Files and final path patterns
- Variants (meaningful output shapes only)
- Conditions and mapped option tokens
- Representative values for doctor and preview

Keep smallest complete shape. No speculative fields, variants, templates, or flexibility.

### 3. Write generator

After approval, create or edit `generator.json` and native templates using current contract. Every referenced template must exist. Every token in templates, paths, and conditions must be declared by field or mapped option. CLI uses complete visible file set; variants define alternatives (no per-template selection).

### 4. Run doctor before preview

```bash
boilersuit generators doctor "<generator-id>" --json \
	--field NAME=example-name
```

Add repeated `--field TOKEN=value` and `--variant id` as needed. Resolve every error, review warnings, supply deferred-check values. Re-run only after changes affecting result. Use `--fail-on-warning` for CI.

### 5. Preview complete result

```bash
boilersuit generate preview "<generator-id>" --json \
	--field NAME=example-name
```

Check: every path, `create`/`skip_existing` action, missing tokens/warnings, variant/field values, complete visible file set. Don't read rendered content by default; inspect only when generator is unfamiliar, placeholder placement risky, or user asks.

### 6. Generate only when requested

Authoring and validating doesn't imply generating examples. Run generation only when user asks:

```bash
boilersuit generate "<generator-id>" --json \
	--field NAME=example-name
```

Use `--skip-existing` only for partial results; preview must show every existing destination that stays unchanged.

## Guardrails

- Contract first; never author from remembered schema details
- Design review before file edits
- Doctor before preview
- Preview before generation
- No removed `--file` or invented `--only` option
- No silent unresolved tokens, missing templates, or ignored doctor errors
- No arbitrary post-generation shell commands
- No overwriting existing files
- Report when a requested behaviour is not supported by the current contract

## Completion

Report:

- Generator directory and templates created or changed
- Doctor result and representative fields used
- Previewed paths and actions
- Whether example files were generated
- Any warnings, deferred checks, or unsupported requirements that remain

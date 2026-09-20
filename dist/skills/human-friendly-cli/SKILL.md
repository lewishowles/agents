---
# Generated — edit skill.json and SKILL.body.md instead.
name: human-friendly-cli
description: >
  Use this skill when designing, reviewing, or extending CLI commands. Covers discoverable, restrained human-first CLIs that also work well for agents.
do-not-use-when:
  - Preparing a library-release
  - Only running an existing CLI command
  - Debugging command output without changing the CLI design
  - Writing a shell script; use bash instead
related-skills:
  - writing
---
# Human-friendly CLI

Design CLIs for people first: clear, structured, restrained, discoverable, predictable. These make CLIs reliable for agents too.

## Core contract

A user who's never seen the command can discover available actions, valid values, likely next step, and failure reason without reading source.

## Command shape

- Prefer explicit subcommands/flags over free-form payloads.
- Keep names stable, short, verb-led: `list`, `info`, `describe`, `preview`, `doctor`, `snippet`, `pattern`, `generate`.
- Use enum-like flag values; list valid values in help/errors.
- Prefer repeated flags or named fields: `--field NAME=value`, `--variant compact`.
- Avoid JSON as primary input when shell quoting common.
- Offer `--json` output for automation.
- Include `--dry-run`, `preview`, or `doctor` for commands that write files, mutate state, or fail late.

## Discovery

Every CLI should let users answer through commands:

- What can this tool do?
- What options exist?
- What valid names/IDs/variants/examples?
- What happens before write?
- What went wrong and what's the fix?

Useful discovery commands: `--help`, `list`, `info`, `describe`, `preview`, `doctor`.

## Help text

- Show common path first.
- Include one realistic copyable example per command.
- Keep examples shell-safe: avoid nested quoting/multiline JSON.
- Mention defaults, required fields, repeatable flags, valid enum values.
- Explain output modes: human by default, `--json` for structure.
- Document both interactive and non-interactive modes if both exist.

## Output

- Readable, scan-friendly, restrained human output.
- Use headings, tables, status rows, panels to clarify structure.
- Success: focus on what changed or what's next.
- Errors: name invalid value, show alternatives, include corrected command.
- Never use colour as only signal.
- Avoid noisy banners, decoration, or repeated prose.

## `@lewishowles/cli-style`

Use `@lewishowles/cli-style` for terminal output unless constrained. Don't hand-roll ANSI codes, tables, panels, colour, or terminal detection.

```js
import { createCliStyle } from "@lewishowles/cli-style";
const ui = createCliStyle({ argv, env, stdout });
```

- Construct `ui` once at entrypoint.
- Thread `ui` through command handlers and print functions.
- Use library helpers for colour, tables, panels, status rows, cancellation.
- Keep colour optional and non-TTY compatible.
- Inject `argv`, `env`, `stdout` explicitly for deterministic test output.

### Other languages

Bash, Python, and Swift adapters call the same binary, so output matches the JavaScript renderers.

Python installs and imports under different names, deliberately: PyPI already had something too close to `cli-style`.

```sh
pip install lewishowles-cli-style
```

```python
from cli_style import render

print(render("status", {"type": "success", "label": "Tests passed"}))
```

- Rendering runs through the `cli-style` binary, which must be on `PATH`.
- Without the binary, `render()` returns plain `key: value` text. Pass `raise_on_missing=True` to fail instead of degrading.

## Agent use follows human use

Don't create separate agent-only CLI unless normal CLI can't expose the action. Prefer constrained commands over prompts, `--help`/`list` over searching, `preview`/`doctor` over trial-and-error, structured output via `--json` not input. Test whether normal CLI can be clearer for humans before adding agent mode.

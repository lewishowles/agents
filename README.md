# Agent configuration

This repository holds Lewis Howles's shared configuration for Claude Code and Codex. You can read it for examples, use selected skills in your own setup, or install the full configuration on macOS.

## How it fits together

- **Rules** in `src/rules/` give both agents instructions that apply in every project.
- **Skills** in `skills/` give an agent guidance for a particular kind of work. Each skill has its own instructions and, sometimes, supporting files.
- **Hooks** in `src/hooks/claude/` respond to Claude Code events. Codex has its own configuration in `src/adapters/codex/`.
- **Scripts** in `scripts/` build the generated configuration, check it, and link the selected parts into your agent directories.

The files in `dist/` are generated from the source files. Edit the source, then regenerate the output with `scripts/sync.sh`.

## Choose your route

### Learn from it

Start with a skill in `skills/` to see its trigger description and instructions. The [skills guide](docs/skills.md) lists the available skills, and the [hooks guide](docs/hooks.md) explains the Claude Code hooks and how Codex differs. You don't need to install anything to read them.

### Reuse some skills

On macOS, run setup from the repository root and choose **Skills only**. It links the skills you select into Claude Code or Codex without installing the full configuration:

```bash
scripts/setup.sh --preset skills-only
```

Setup shows its plan before applying changes. Most skills are selected by default; the Apple collection is optional. See [choose which skills to install](docs/setup.md#choose-which-skills-to-install) for the selection options, including how to opt in to the Apple collection.

### Install everything

On macOS, run setup from the repository root and choose **Everything**, or select it directly:

```bash
scripts/setup.sh --preset everything
```

The plan includes rules, skills, hooks and the supporting tools for Claude Code and Codex. Review it before confirming. The [setup guide](docs/setup.md) covers manual wiring and troubleshooting. If you're moving to another machine, read [what setup can't restore](docs/setup.md#what-setup-cant-restore) before relying on previous task records or logins.

## Requirements

The setup scripts are for macOS and require a terminal with Claude Code or Codex installed. Regeneration and validation need Bash 4 or newer; validation also needs coreutils for `timeout`. macOS's Bash 3.2 is too old. Claude's hooks need `jq`. With Homebrew, install these tools using:

```bash
brew install bash coreutils jq
```

Setup may need the local `agent-tools` checkout and `uv` to install helper commands. It checks for them before making changes and tells you what is missing. The [setup guide](docs/setup.md#choose-which-skills-to-install) has the details.

## First use

After setup, check which skills are linked and which are available to opt in:

```bash
scripts/setup.sh --status
```

For example, ask your agent to review a README. The `writing` skill gives it a reader-first structure and covers voice and plain language. Skills are discovered from their descriptions when the task matches.

## Repository map

| Path                | What you'll find                                |
| ------------------- | ----------------------------------------------- |
| `src/rules/`        | Shared instructions for both agents             |
| `skills/`           | Task-specific skills and their supporting files |
| `src/hooks/claude/` | Claude Code hook sources                        |
| `src/adapters/`     | Agent-specific configuration sources            |
| `scripts/`          | Setup, generation and validation scripts        |
| `docs/`             | Guides and reference pages                      |
| `dist/`             | Generated output for installation               |

## More information

- [Setup and recovery](docs/setup.md)
- [Working with HCOM teams](docs/hcom.md)
- [Available skills](docs/skills.md)
- [Hook behaviour](docs/hooks.md)
- [Catppuccin skin for Claude Code](src/plugins/skin/README.md)
- [MIT licence](LICENSE)

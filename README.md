# Global agent configuration

Shared configuration for Claude Code and Codex, this repository keeps common agent rules, skills, hooks, and project templates in one place.

## Set up global configuration

This links the rules, skills, and hooks in this repo into your Claude and Codex home configuration, so every project you open picks them up automatically. Run it from the repository root:

```bash
scripts/setup-global.sh --both
```

Setup links every skill into Claude and Codex by default, one symlink per skill. Edits to a linked skill take effect without rebuilding. Use `--exclude` to leave skills out, `--include` to add them back, `--include-all` to restore the full set, `--status` to check the links, or `--select` to choose interactively. See [choosing skills](docs/setup.md#choose-which-skills-to-install) for examples.

Claude uses skill-trigger hooks to automatically load the right skill for what you're doing, and those hooks need `jq` to run. Install it with `brew install jq` before running the command if you use Claude.

## Set up a project

Global skills work without project setup. This optional step adds project instructions (`AGENTS.md`, `CLAUDE.md`, and `.claudeignore` where applicable), optional skill-pack links, and the global `project-checks` and `friction` tools. It lists what it will add before changing anything. Run it from the project root:

```bash
/path/to/repository/scripts/setup-project.sh --both
```

## Read next

- [Setup](docs/setup.md): manual wiring, troubleshooting, and token usage reports
- [Skills](docs/skills.md): available skills and trigger behaviour
- [Commands](docs/commands.md): built-in and custom commands
- [Hooks](docs/hooks.md): Claude and Codex hook behaviour

## Shell aliases

I recommend adding an alias to `~/.zshrc` if you run global setup often:

```bash
alias setup:agents:global="/path/to/repository/scripts/setup-global.sh --both"
```

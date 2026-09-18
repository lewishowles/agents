# Global agent configuration

Shared configuration for Claude Code and Codex, this repository keeps common agent rules, skills, hooks, and project templates in one place.

## Set up global configuration

This links the rules, skills, and hooks in this repo into your Claude and Codex home configuration, so every project you open picks them up automatically. Run it from the repository root:

```bash
scripts/setup-global.sh --both
```

Claude uses skill-trigger hooks to automatically load the right skill for what you're doing, and those hooks need `jq` to run. Install it with `brew install jq` before running the command if you use Claude.

## Set up a project

This creates the project's `AGENTS.md` and other per-project config. Run it from the project root:

```bash
/path/to/repository/scripts/setup-project.sh --both
```

## Read next

- [Setup](docs/setup.md): manual wiring, troubleshooting, and token usage reports
- [Skills](docs/skills.md): available skills and trigger behaviour
- [Commands](docs/commands.md): built-in and skill commands
- [Hooks](docs/hooks.md): Claude and Codex hook behaviour

## Shell aliases

I recommend adding an alias to `~/.zshrc` if you run global setup often:

```bash
alias setup:agents:global="/path/to/repository/scripts/setup-global.sh --both"
```

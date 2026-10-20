# Global agent configuration

Shared configuration for Claude Code and Codex, this repository keeps common agent rules, skills, and hooks in one place.

## Set up global configuration

This links the rules, skills, and hooks in this repo into your Claude and Codex home configuration, so every project you open picks them up automatically. It also links the trash wrapper to `~/.local/bin/trash` for both agents and your shell. The wrapper refuses empty paths, your current folder, and its ancestors, which helps prevent an unset variable from moving a whole project to the Trash. It takes effect only when `~/.local/bin` comes before `/usr/bin` on `PATH`; `type -a trash` shows which command runs first. Run setup from the repository root:

```bash
scripts/setup-global.sh --both
```

Setup links every skill into Claude and Codex by default, one symlink per skill. Edits to a linked skill take effect without rebuilding. Use `--exclude` to leave skills out, `--include` to add them back, `--include-all` to restore the full set, `--status` to check the links, or `--select` to choose interactively. See [choosing skills](docs/setup.md#choose-which-skills-to-install) for examples.

Several of Claude's hooks need `jq` to run. Install it with `brew install jq` before running the command if you use Claude.

## Read next

- [Setup](docs/setup.md): manual wiring, troubleshooting, and token usage reports
- [Skills](docs/skills.md): available skills and trigger behaviour
- [Commands](docs/commands.md): commands provided by this repository
- [Hooks](docs/hooks.md): Claude and Codex hook behaviour

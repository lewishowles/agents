# Global agent configuration

Shared configuration for Claude Code and Codex, this repository keeps common agent rules, skills, and hooks in one place.

`scripts/sync.sh` and `scripts/validate.sh` need Bash 4 or newer, and validation also needs coreutils for `timeout`. macOS ships Bash 3.2, so install both with `brew install bash coreutils`.

## Set up global configuration

With the **Everything** preset, setup links the rules, skills, hooks and trash wrapper into your Claude and Codex home configuration. **Pick features** links the chosen agents' rules and skills, plus the extras you choose. The trash wrapper goes to `~/.local/bin/trash` for both agents and your shell. It refuses empty paths, your current folder, and its ancestors, which helps prevent an unset variable from moving a whole project to the Trash. It takes effect only when `~/.local/bin` comes before `/usr/bin` on `PATH`; `type -a trash` shows which command runs first. Run setup from the repository root:

```bash
scripts/setup.sh
```

In a terminal, setup asks whether to link skills only, pick features or install everything, then shows the planned changes before applying them. Use `--preset skills-only`, `--preset pick` or `--preset everything` to skip the preset question. Setup links every skill except the Apple collection, one symlink per skill, so edits to a linked skill take effect without rebuilding. Choose Apple in `--select` or include one of its skills to opt in; setup remembers the choice. Use `--exclude` to leave skills out, `--include` to add them back, `--include-all` to restore the full set, `--status` to check the links, or `--select` to pick skills from a list grouped by collection with a short description of each. See [choosing skills](docs/setup.md#choose-which-skills-to-install) for examples.

Several of Claude's hooks need `jq` to run. Install it with `brew install jq` before running the command if you use Claude.

## Read next

- [Setup](docs/setup.md): manual wiring, troubleshooting, and token usage reports
- [Skills](docs/skills.md): available skills and trigger behaviour
- [Hooks](docs/hooks.md): Claude and Codex hook behaviour

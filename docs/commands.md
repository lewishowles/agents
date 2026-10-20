# Commands

Type the commands provided by this repository in Claude Code with a `/` prefix. For built-in commands, see the [official Claude Code documentation](https://code.claude.com/docs/en/commands).

## Custom commands

Slash commands can be defined as plain markdown files. Claude Code reads them as additional instructions when invoked.

- **Global commands** live in `~/.claude/commands/` and are available in every project. `scripts/setup-global.sh` symlinks everything in `dist/claude/commands/` there automatically.
- **Project commands** live in `.claude/commands/` at the project root and are only available in that project.

The file name becomes the command: `new-command.md` → `/new-command`.

| Command        | What it does                                                  |
| -------------- | ------------------------------------------------------------- |
| `/new-command` | Scaffold a new slash command file with the standard structure |

# Commands

Type commands in Claude Code with a `/` prefix. The built-in commands and skills you can invoke this way are listed below.

## Built-in Claude Code commands

These are provided by Claude Code itself and are always available.

| Command        | What it does                                              |
| -------------- | --------------------------------------------------------- |
| `/help`        | List available commands and keyboard shortcuts            |
| `/clear`       | Clear the current conversation context                    |
| `/compact`     | Summarise the conversation to free up context space       |
| `/config`      | Open Claude Code settings (theme, model, etc.)            |
| `/model`       | Switch the active model (e.g. `/model claude-sonnet-4-6`) |
| `/cost`        | Show token usage and estimated cost for the session       |
| `/status`      | Show current session status                               |
| `/init`        | Initialise a new `CLAUDE.md` in the current project       |
| `/review`      | Review a pull request                                     |
| `/fast`        | Toggle fast mode (Opus 4.6 with faster output)            |
| `/vim`         | Toggle Vim keybindings                                    |
| `/bug`         | Report a Claude Code bug                                  |
| `/pr_comments` | Fetch comments from a GitHub pull request                 |

## Custom commands

Slash commands can be defined as plain markdown files. Claude Code reads them as additional instructions when invoked.

- **Global commands** live in `~/.claude/commands/` and are available in every project. `scripts/setup-global.sh` symlinks everything in `dist/claude/commands/` there automatically.
- **Project commands** live in `.claude/commands/` at the project root and are only available in that project.

The file name becomes the command: `new-command.md` → `/new-command`.

| Command        | What it does                                                  |
| -------------- | ------------------------------------------------------------- |
| `/new-command` | Scaffold a new slash command file with the standard structure |

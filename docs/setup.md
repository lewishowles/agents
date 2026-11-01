# Setup

Use the scripts for normal installs, and add a shell alias if you run them often. The manual steps after that are a fallback for when you need to inspect or repair the wiring.

`scripts/sync.sh` and `scripts/validate.sh` need Bash 4 or newer, and validation also needs coreutils for `timeout`. macOS ships Bash 3.2, so install both with `brew install bash coreutils`.

Both scripts use `CLI_STYLE_BIN` when it is set, or the globally installed `cli-style` command from `PATH`. If it is missing, install it with `bun add -g @lewishowles/cli-style` or `npm install -g @lewishowles/cli-style`. Full project setup installs it globally when needed, using Bun when available and npm otherwise.

## Shell aliases

Add this alias to `~/.zshrc`:

```bash
alias setup:agents="/path/to/repository/scripts/setup.sh --both"
```

## Global Claude setup

Run `scripts/sync.sh`, then link these paths:

```bash
ln -s /path/to/repository/dist/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -s /path/to/repository/dist/claude/settings.json ~/.claude/settings.json
ln -s /path/to/repository/dist/claude/.mcp.json ~/.claude/.mcp.json
```

Create `~/.claude/skills/` and `~/.claude/hooks/`, then link each item individually:

```bash
ln -s /path/to/repository/skills/vue/vue ~/.claude/skills/vue
```

Repeat for each skill and hook. Per-item links allow plugin-installed items to coexist.

This repo ships the skin plugin in `src/plugins/skin/`. It adds Catppuccin colours to Claude Code tool rows, Bash results and turn footers, and draws Markdown tables as boxed grids. Global setup does not install it; try it with `claude --plugin-dir /path/to/repository/src/plugins/skin`. Add other Claude Code plugins with `/plugin install <plugin-name>@<marketplace>`; they coexist with this repo's linked skills and hooks.

## Global Codex setup

Run `scripts/sync.sh`, then link:

```bash
ln -s /path/to/repository/dist/codex/AGENTS.md ~/.agents/AGENTS.md
ln -s /path/to/repository/dist/codex/AGENTS.md ~/.codex/AGENTS.md
```

Merge `src/adapters/codex/config.base.toml` into `~/.codex/config.toml` so existing desktop preferences, trusted projects, hook trust, plugins, and unrelated servers stay intact. `scripts/sync.sh` generates the `dist/codex/AGENTS.md` target used by both links above.

Ensure `~/.codex/config.toml` includes:

```toml
approval_policy = "never"
sandbox_mode = "workspace-write"

[mcp_servers.codebase-memory-mcp]
command = "codebase-memory-mcp"
```

codebase-memory-mcp does not auto-index by default. From a project root, index manually with:

```bash
codebase-memory-mcp cli index_repository '{"repo_path":"'$PWD'"}'
```

After indexing, review the architecture summary and store an ADR so future sessions have durable project context:

```bash
codebase-memory-mcp cli get_architecture '{"project":"Users-lewis-Dev-Repositories-example","aspects":["all"]}'
codebase-memory-mcp cli manage_adr '{"project":"Users-lewis-Dev-Repositories-example","mode":"update","content":"Architecture notes from get_architecture"}'
```

If `get_architecture` errors with `aspects:["all"]`, run it without `aspects`. Some CLI versions advertise `manage_adr(mode="store")`, but the current MCP schema uses `mode="update"`.

For zsh, add a helper like this:

```zsh
index:repository() {
	if ! command -v codebase-memory-mcp &>/dev/null; then
		printf 'codebase-memory-mcp is not installed or not on PATH\n' >&2
		return 1
	fi

	if ! command -v jq &>/dev/null; then
		printf 'jq is required to build JSON payloads safely\n' >&2
		return 1
	fi

	local repo_path index_output project architecture

	repo_path="${PWD:A}"
	index_output="$(codebase-memory-mcp cli index_repository "$(jq -cn --arg repo_path "$repo_path" '{repo_path:$repo_path}')")" || return
	project="$(printf '%s' "$index_output" | jq -r '.project // empty' 2>/dev/null)"

	if [[ -z "$project" ]]; then
		project="$(codebase-memory-mcp cli list_projects '{}' | jq -r --arg repo_path "$repo_path" 'first(.projects[] | select(.root_path == $repo_path) | .name) // empty')"
	fi

	if [[ -z "$project" ]]; then
		printf 'Could not find an indexed project for %s\n' "$repo_path" >&2
		printf '%s\n' "$index_output" >&2
		return 1
	fi

	if [[ -n "$index_output" ]]; then
		printf '%s\n' "$index_output"
	fi

	architecture="$(codebase-memory-mcp cli get_architecture "$(jq -cn --arg project "$project" '{project:$project,aspects:["all"]}')" 2>/dev/null || codebase-memory-mcp cli get_architecture "$(jq -cn --arg project "$project" '{project:$project}')")" || return
	printf '%s\n' "$architecture"

	codebase-memory-mcp cli manage_adr "$(jq -cn --arg project "$project" --arg content "$architecture" '{project:$project,mode:"update",content:$content}')"
}
```

Or, inside Claude/Codex when the MCP tools are available, call `index_repository` with the current repository path. Check indexed projects with:

```bash
codebase-memory-mcp cli list_projects '{}'
```

Create `~/.agents/skills/`, then link each skill folder:

```bash
ln -s /path/to/repository/skills/vue/vue ~/.agents/skills/vue
```

This keeps Codex skill discovery under `~/.agents` while `~/.codex` holds app config and hooks.

When `hcom` is installed, `scripts/setup.sh --codex` (or `--both`) also adds folders to the list HCOM passes to the Codex agents it starts (`hcom config codex_args`). Those agents can then write to this repository, `~/.agents`, `~/.Trash`, and the SwiftPM cache and settings folders (`~/Library/Caches/org.swift.swiftpm` and `~/Library/org.swift.swiftpm`) from inside the sandbox. Setup only adds folders that exist on this machine, and it keeps any folders you added yourself. Running agents keep the list they started with, so relaunch them from a fresh terminal after the list changes.

## Install the agent configuration

Run `scripts/setup.sh` to set up both agents, or pass `--claude` or `--codex` for one agent. Setup installs the selected agents' configuration, hooks, skills, themes, helper commands, the trash wrapper, and any relevant Codex settings or HCOM additions.

The trash wrapper goes to `~/.local/bin/trash` for both agents and your shell. It refuses empty paths, your home folder, your current folder and its ancestors, which stops an unset variable from moving a whole project to the Trash. It only takes effect when `~/.local/bin` comes before `/usr/bin` on `PATH`; run `type -a trash` to see which command runs first.

Setup links every skill, including Apple skills, unless its name appears in `scripts/skill-exclusions.txt`. The list belongs to this repository and applies to both agents. Each skill has its own symlink, so edits to a skill take effect without rebuilding. A skill added to the repository is linked the next time you run setup.

Run `scripts/doctor.sh` to check the installation without changing it. When Claude or Codex is set up in this home, the doctor lists what setup would change, including shared items such as the trash link and Git hooks. It groups each planned change by kind and counts it as a required problem. When setup has nothing to change, the doctor says so. Missing cli-style also fails, with global install commands; `hcom` and `uv` are optional. The skill status section shows installed, excluded, missing, and conflicting skills for information, while the setup changes section counts the links that need work. The doctor also reports unreadable Codex settings, duplicate skill names, and stale entries in the repository exclude list.

If a file or folder that setup did not create already sits where a skill's link belongs, setup moves it to a timestamped `.bak` backup under `~/.claude/backups/skills/` or `~/.agents/backups/skills/` and prints `backup at <path>`. Content at an excluded skill's name is left untouched.

Setup applies changes straight away and reports each step as it runs. It backs up files it replaces and removes older backups of those files. If everything is already set up, it prints `Nothing to change.` and exits successfully. Use `scripts/doctor.sh` to check an installation without changing it.

Setup writes `~/.codex/config.toml` in a fixed layout. If your copy uses different spacing or section order, the next run rewrites it once and saves a backup first.

Before changing files, global setup checks that the selected agent's helper commands are installed or can be installed from the local agent-tools checkout with `uv`. Claude needs `friction`, `team-send`, and `doc-paths`; Codex needs `team-send` and `doc-paths`. If a required command is missing and `uv` or its source package under `~/Dev/Repositories/Packages/agent-tools` is unavailable, setup lists each missing command and the fix, then stops without changing the installation.

## What setup can't restore

Setup links this repository's configuration and skills. Keep separate backups of the local state you want on another machine:

- **Progress history:** `progress` stores projects, tasks, decisions, and handoffs in `~/.agents/progress.db` by default, or in the file named by `AGENTS_PROGRESS_DATABASE`. Back up that database and restore it separately before relying on earlier task records. Run `progress summary --json` to find the restored project IDs, then run `progress project attach <project_id>` in each fresh clone. Without a backup, run `progress project init --slug <slug> --name <name>` in each project directory to create new records.
- **Tool logins:** sign in to Claude Code, Codex, and any connected services again after setup. Setup doesn't transfer their login state.
- **HCOM state:** HCOM keeps its configuration, message history, and handoff files under `~/.hcom/`. Back up and restore that folder separately if you need its history. Otherwise, run `cont` from the project directory to start a new team and resume from the task's saved handoff in `progress`, if you restored the progress database. See [the HCOM guide](hcom.md) for the team workflow.

## Register project commands

From the project root, preview likely commands and register the ones agents may run:

```bash
cd /path/to/project
agent-run detect --json
agent-run detect --add <name>
agent-run list --json
```

Repeat `agent-run detect --add <name>` for named commands, or use `agent-run detect --all` to register every likely command. Run a registered command with:

```bash
agent-run run <name> --json
```

Run a one-off command with `agent-run run --json -- <argv>`. Manual-only commands are refused with code `manual` and the command to run. The manual-command guard also blocks them and raw Playwright/Cypress commands.

The default output omits the broad file tree. Pass `--tree-depth <number>` when a tree is useful.

Put durable repository facts and gotchas in `AGENTS.md`, usage instructions in ordinary docs, and project commands or manual-only rules in agent-run's per-repo registrations. Keep each source focused on information agents can act on.

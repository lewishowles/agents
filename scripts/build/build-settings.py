#!/usr/bin/env python3
# Generate dist/claude/settings.json from src/adapters/claude/settings.base.json
# and src/hooks/claude/*/hook.json.
#
# The base file holds env, permissions, skillOverrides, and a single inline hook
# entry (the .env read-guard) that cannot be expressed as a named hook script.
# All other hooks are derived from src/hooks/claude/*/hook.json.
#
# Hooks without a .sh extension use a top-level or event-level 'command' field
# in hook.json to override the default bash-wrapper command.

import json
from pathlib import Path

# The repository root, so the script finds its files from any working directory.
REPO_DIR = Path(__file__).resolve().parent.parent.parent
# The hand-edited settings file that the generated settings start from.
BASE_FILE = (
	REPO_DIR / "src" / "adapters" / "claude" / "settings.base.json"
)
# The folder of Claude hook manifests whose hooks are added to the settings.
HOOKS_DIR = REPO_DIR / "src" / "hooks" / "claude"
# The generated settings file that Claude reads.
OUT_FILE = REPO_DIR / "dist" / "claude" / "settings.json"


# Return the shell command string that invokes a hook.
# Hooks with a 'command' field use it directly. All others are wrapped in a
# bash -c invocation so the hook runs with the user's shell environment.
#
# @param  {dict}  manifest
#     The hook's hook.json contents.
def hook_command(manifest: dict) -> str:
	if "command" in manifest:
		return manifest["command"]
	# The hook's name, which is also the name of its installed .sh script.
	name = manifest["name"]
	return f"bash -c 'bash \"$HOME/.claude/hooks/{name}.sh\"'"


# Build a single hook entry for the settings.json hooks block.
#
# @param  {dict}  hook_def
#     The event definition from the manifest's events array.
# @param  {str}   command
#     The command string returned by hook_command.
def build_hook_entry(hook_def: dict, command: str) -> dict:
	# The command entry, with any timeout or status message the event sets.
	entry: dict = {"type": "command", "command": command}
	if "timeout" in hook_def:
		entry["timeout"] = hook_def["timeout"]
	if "statusMessage" in hook_def:
		entry["statusMessage"] = hook_def["statusMessage"]
	return entry


def main() -> None:
	# The hand-edited settings, which become the output once the hook entries are added.
	base = json.loads(BASE_FILE.read_text())
	# The hooks section of the settings, created when the base file has none.
	hooks_block: dict = base.setdefault("hooks", {})

	# The hooks for each event and matcher pair, batched so each pair becomes one
	# settings entry.
	groups: dict[tuple, list] = {}

	for hook_dir in sorted(HOOKS_DIR.iterdir()):
		# The hook's hook.json file; folders without one are skipped.
		manifest_file = hook_dir / "hook.json"
		if not manifest_file.exists():
			continue
		# The hook's name, default command and events from its hook.json.
		manifest = json.loads(manifest_file.read_text())

		for ev in manifest.get("events", []):
			# The command for this event: its own command when set, otherwise the hook's default.
			command = ev.get("command")
			if command is None:
				command = hook_command(manifest)
			# The event and matcher pair that groups hooks into one settings entry.
			key = (ev["event"], ev.get("matcher"))
			groups.setdefault(key, []).append((manifest["name"], command, ev))

	for entries in groups.values():
		entries.sort(key=lambda x: x[0])

	for (event, matcher), entries in sorted(
		groups.items(), key=lambda kv: (kv[0][0], kv[0][1] or "")
	):
		# The command entries for every hook in this group.
		hook_entries = [build_hook_entry(ev, cmd) for _, cmd, ev in entries]
		# The settings entries for this event, which this group is added to.
		event_list: list = hooks_block.setdefault(event, [])
		if matcher:
			event_list.append({"matcher": matcher, "hooks": hook_entries})
		else:
			event_list.append({"hooks": hook_entries})

	OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
	OUT_FILE.write_text(json.dumps(base, indent=2) + "\n")
	print(f"Generated {OUT_FILE.relative_to(REPO_DIR)}")


if __name__ == "__main__":
	main()

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

# Anchor input and output paths to this repository.
REPO_DIR = Path(__file__).resolve().parent.parent.parent
# Editable settings source.
BASE_FILE = (
	REPO_DIR / "src" / "adapters" / "claude" / "settings.base.json"
)
# Find the Claude hook manifests to register in settings.
HOOKS_DIR = REPO_DIR / "src" / "hooks" / "claude"
# Write the settings file used by Claude.
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
	# Use the hook's name to find its installed shell script.
	name = manifest["name"]
	return f"bash -c 'bash \"$HOME/.claude/hooks/{name}.sh\"'"


# Build a single hook entry for the settings.json hooks block.
#
# @param  {dict}  hook_def
#     The event definition from the manifest's events array.
# @param  {str}   command
#     The command string returned by hook_command.
def build_hook_entry(hook_def: dict, command: str) -> dict:
	# Build the command definition stored under a hook event.
	entry: dict = {"type": "command", "command": command}
	if "timeout" in hook_def:
		entry["timeout"] = hook_def["timeout"]
	if "statusMessage" in hook_def:
		entry["statusMessage"] = hook_def["statusMessage"]
	return entry


def main() -> None:
	# Load the settings that remain editable outside hook manifests.
	base = json.loads(BASE_FILE.read_text())
	# Add generated hook registrations to the settings object.
	hooks_block: dict = base.setdefault("hooks", {})

	# Group hooks by (event, matcher) so hooks for the same event are batched
	# together in the output, matching the structure Claude's settings expect.
	groups: dict[tuple, list] = {}

	for hook_dir in sorted(HOOKS_DIR.iterdir()):
		# Locate the hook definition within this hook's directory.
		manifest_file = hook_dir / "hook.json"
		if not manifest_file.exists():
			continue
		# Read the hook's commands and registered events.
		manifest = json.loads(manifest_file.read_text())

		for ev in manifest.get("events", []):
			# Use this event's command when it overrides the hook command.
			command = ev.get("command")
			if command is None:
				command = hook_command(manifest)
			# Batch hooks that share an event and matcher.
			key = (ev["event"], ev.get("matcher"))
			groups.setdefault(key, []).append((manifest["name"], command, ev))

	for entries in groups.values():
		entries.sort(key=lambda x: x[0])

	for (event, matcher), entries in sorted(
		groups.items(), key=lambda kv: (kv[0][0], kv[0][1] or "")
	):
		# Build the commands for this event and matcher.
		hook_entries = [build_hook_entry(ev, cmd) for _, cmd, ev in entries]
		# Append this batch to the event's settings entries.
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

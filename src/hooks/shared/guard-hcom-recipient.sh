#!/usr/bin/env bash
# Blocks an `hcom send` that names no @recipient before the message body.
# A reply that relies on --reply-to alone sits unread in the original sender's
# queue without waking it, so every send must name its recipient. An @ inside
# the message text, a --file body or a heredoc body never counts.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input="$(cat)"  # PreToolUse payload from the agent runtime.
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0  # Tool about to run.
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0  # Shell command about to run.
[[ -n "$command_str" ]] || exit 0

# Python splits the command into separate shell commands and arguments, which
# a shell pattern cannot do reliably once quotes and heredocs are involved.
python3 - "$command_str" <<'PY'
import re
import shlex
import sys


# Returns the command with heredoc bodies and unquoted # comments removed.
# A heredoc body is message text, so an @ or `hcom send` inside it must not
# count. A comment is removed because an apostrophe in it would otherwise open
# a quote that swallows the lines after it. A `<<` inside quotes is ordinary
# text, not a heredoc.
#
# @param  {str}  command
#     The full shell command from the tool call.
def without_heredoc_bodies(command: str) -> str:
	kept = []  # Command lines outside any heredoc body.
	delimiters = []  # End markers of the heredocs still open, in order.
	quote = None  # The open quote character across command lines.
	heredoc = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")  # A heredoc operator, never a `<<<` here-string, and its end marker, which may be quoted.

	for line in command.splitlines(keepends=True):
		if delimiters:
			if line.strip() == delimiters[0]:
				delimiters.pop(0)
			continue

		escaped = False  # Whether the previous character was a backslash.
		comment_start = len(line)  # Where an unquoted # comment starts (a # at the start of a word), or the line length when there is none.

		for index, character in enumerate(line):
			if escaped:
				escaped = False
				continue

			if character == "\\" and quote != "'":
				escaped = True
				continue

			if quote:
				if character == quote:
					quote = None
				continue

			if character in "'\"":
				quote = character
				continue

			if character == "#" and (index == 0 or line[index - 1].isspace() or line[index - 1] in ";&|()<>"):
				comment_start = index
				break

			if character == "<":
				match = heredoc.match(line, index)
				if match:
					delimiters.append(match.group(2))

		kept.append(line[:comment_start] + ("\n" if comment_start < len(line) and line.endswith("\n") else ""))

	return "".join(kept)


# Splits a compound command into its separate commands at `;`, `&`, `|`,
# newlines, brackets and backticks, ignoring those characters inside quotes.
#
# @param  {str}  command
#     The shell command with heredoc bodies already removed.
def shell_commands(command: str) -> list[str]:
	commands = []  # Finished commands.
	current = []  # Characters of the command being read.
	quote = None  # The open quote character, if inside a quoted string.
	escaped = False  # Whether the previous character was a backslash.

	for character in command:
		if escaped:
			current.append(character)
			escaped = False
			continue

		if character == "\\" and quote != "'":
			current.append(character)
			escaped = True
			continue

		if quote:
			current.append(character)
			if character == quote:
				quote = None
			continue

		if character in "'\"":
			quote = character
			current.append(character)
		elif character in ";&|\n(){}`":
			commands.append("".join(current))
			current = []
		else:
			current.append(character)

	commands.append("".join(current))
	return commands


# Returns True when any `hcom send` in the command has no @recipient before
# `--`. hcom is recognised by any path ending in hcom, with or without global
# options before `send`. Values of --file and --base64 are skipped, so a path
# or encoded body starting with @ does not count. A send that asks for --help
# or -h is allowed, and so is a command that cannot be parsed.
#
# @param  {str}  command
#     The full shell command from the tool call.
def missing_recipient(command: str) -> bool:
	for segment in shell_commands(without_heredoc_bodies(command)):
		try:
			words = shlex.split(segment)  # The command's arguments, unquoted.
		except ValueError:
			continue

		while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
			words.pop(0)

		if words[:1] == ["command"]:
			words.pop(0)

		if not words or words[0].rsplit("/", 1)[-1] != "hcom":
			continue

		position = 1  # The position of the hcom subcommand, after any global options such as --name x.
		while position < len(words) and words[position].startswith("-"):
			position += 2 if words[position] == "--name" else 1

		if words[position:position + 1] != ["send"]:
			continue

		arguments = iter(words[position + 1:])  # The send options and recipients, read in order.
		for argument in arguments:
			if argument == "--":
				break
			if argument in {"--help", "-h"}:
				break
			if argument in {"--file", "--base64"}:
				next(arguments, None)
				continue
			if argument.startswith("@"):
				break
		else:
			return True

		if argument == "--":
			return True

	return False


if missing_recipient(sys.argv[1]):
	print(
		"guard-hcom-recipient: blocked: this hcom send names no recipient, so nobody would be woken by it. Nothing in this command ran. Add the recipient's role tag, such as @<repo>-<role>-, before the message body; --reply-to alone does not deliver a message.",
		file=sys.stderr,
	)
	sys.exit(2)
PY

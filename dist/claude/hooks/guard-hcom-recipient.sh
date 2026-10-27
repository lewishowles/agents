#!/usr/bin/env bash
# Blocks an `hcom send` that names no recipient, and stops core team roles
# (orchestrator, scout, implementer, reviewer) from sending to a role tag,
# which can wake a replaced peer; they must use team-send instead.
# A reply that relies on --reply-to alone sits unread in the original sender's
# queue without waking it, so every send must name its recipient. An @ inside
# the message text, a --file body or a heredoc body never counts.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# PreToolUse payload from the agent runtime.
input="$(cat)"
# Tool about to run.
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

# Shell command about to run.
command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# Python splits the command into separate shell commands and arguments, which
# a shell pattern cannot do reliably once quotes and heredocs are involved.
python3 - "$command_str" <<'PY'
import os
import re
import shlex
import sys
from typing import Iterator, Optional


# Roles that must route messages through team-send.
CORE_ROLES = {"orchestrator", "scout", "implementer", "reviewer"}


# Returns the command with heredoc bodies and unquoted # comments removed.
# A heredoc body is message text, so an @ or `hcom send` inside it must not
# count. A comment is removed because an apostrophe in it would otherwise open
# a quote that swallows the lines after it. A `<<` inside quotes is ordinary
# text, not a heredoc.
#
# @param  {str}  command
#     The full shell command from the tool call.
def without_heredoc_bodies(command: str) -> str:
	# Command lines outside any heredoc body.
	kept = []
	# End markers of the heredocs still open, in order.
	delimiters = []
	# The open quote character across command lines.
	quote = None
	# A heredoc operator, never a `<<<` here-string, and its end marker, which may be quoted.
	heredoc = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

	for line in command.splitlines(keepends=True):
		if delimiters:
			if line.strip() == delimiters[0]:
				delimiters.pop(0)
			continue

		# Whether the previous character was a backslash.
		escaped = False
		# Where an unquoted # comment starts (a # at the start of a word), or the line length when there is none.
		comment_start = len(line)

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
	# Finished commands.
	commands = []
	# Characters of the command being read.
	current = []
	# The open quote character, if inside a quoted string.
	quote = None
	# Whether the previous character was a backslash.
	escaped = False

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


# Returns the core role at the end of a tag, if it has one.
#
# @param  {str}  tag
#     The sender's HCOM tag or a recipient tag without its @ prefix.
def core_role(tag: str) -> Optional[str]:
	# The last hyphen-separated part of the tag, where team tags carry the role.
	role = tag.rsplit("-", 1)[-1]
	return role if role in CORE_ROLES else None


# Returns the core role named by a recipient tag, if it has one.
#
# @param  {str}  recipient
#     An @recipient argument, such as @agent-tools-scout-.
def recipient_role(recipient: str) -> Optional[str]:
	return core_role(recipient[1:].removesuffix("-"))


# Yields the recipients of each `hcom send` that would run. A send asking
# for help is skipped. hcom is recognised by any path ending in hcom, with
# or without global options before `send`. Values of --file and --base64
# are skipped, so a body starting with @ does not count. Commands that
# cannot be parsed are skipped.
#
# @param  {str}  command
#     The full shell command from the tool call.
def send_recipients(command: str) -> Iterator[list[str]]:
	for segment in shell_commands(without_heredoc_bodies(command)):
		try:
			# The command's arguments, unquoted.
			words = shlex.split(segment)
		except ValueError:
			continue

		while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
			words.pop(0)

		if words[:1] == ["command"]:
			words.pop(0)

		if not words or words[0].rsplit("/", 1)[-1] != "hcom":
			continue

		# The position of the hcom subcommand, after any global options such as --name x.
		position = 1
		while position < len(words) and words[position].startswith("-"):
			position += 2 if words[position] == "--name" else 1

		if words[position:position + 1] != ["send"]:
			continue

		# The send options and recipients, read in order.
		arguments = iter(words[position + 1:])
		# Recipients named before the message body.
		recipients = []
		for argument in arguments:
			if argument == "--":
				yield recipients
				break
			if argument in {"--help", "-h"}:
				break
			if argument in {"--file", "--base64"}:
				next(arguments, None)
				continue
			if argument.startswith("@"):
				recipients.append(argument)
		else:
			yield recipients


# The sender's core role from its HCOM tag, or None for anyone else.
sender_role = core_role(os.environ.get("HCOM_TAG", ""))

for recipients in send_recipients(sys.argv[1]):
	if not recipients:
		# The fix to suggest: team-send for core roles, a role tag for anyone else.
		if sender_role:
			message = "this hcom send names no recipient, so nobody would be woken by it. Nothing in this command ran. Use team-send <role> to reach the live teammate; if team-send refuses, report that instead of sending by hand. --reply-to alone does not deliver a message."
		else:
			message = "this hcom send names no recipient, so nobody would be woken by it. Nothing in this command ran. Add the recipient's role tag, such as @<repo>-<role>-, before the message body; --reply-to alone does not deliver a message."
		print(
			f"guard-hcom-recipient: blocked: {message}",
			file=sys.stderr,
		)
		sys.exit(2)

	if sender_role:
		for recipient in recipients:
			# The core role named by this recipient, if it is a role tag.
			role = recipient_role(recipient)
			if role:
				print(
					f"guard-hcom-recipient: blocked: this hcom send targets a role tag. Nothing in this command ran. Use team-send {role} to reach the live teammate; if team-send refuses, report that instead of sending by hand.",
					file=sys.stderr,
				)
				sys.exit(2)
PY

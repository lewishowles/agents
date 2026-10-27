#!/usr/bin/env bash
# Blocks broad searches that bypass ignore rules or enter generated and cached directories.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# The hook payload, read from standard input.
input="$(cat)"
# The tool the agent is about to call.
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

# The shell command the agent wants to run.
command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# Returns the reason a search command must be blocked, or an empty string when it is safe.
#
# @param  {string}  command
#     Shell command from the Bash tool payload.
blocked_search_reason() {
	python3 - "$1" <<'PY'
"""Find broad or protected search paths in a submitted shell command."""

import os
import re
import shlex
import sys
from typing import Optional

# Shell operators that end a simple command.
COMMAND_SEPARATORS = {"&", "&&", ";", ";;", "|", "||"}
# Directory names a search may not target, such as dependency, build and cache folders.
PROTECTED_DIRECTORIES = {
	".cache",
	".caches",
	".git",
	".playwright",
	"build",
	"coverage",
	"dist",
	"ms-playwright",
	"node_modules",
	"playwright-report",
	"test-results",
}
# Search paths that cover the home folder, the current or parent folder, or the filesystem root.
ROOT_PATHS = {"$HOME", "$PWD", "${HOME}", "${PWD}", ".", "..", "../", "./", "/", "~"}
# Ripgrep options that consume the following argument as a value.
RG_OPTIONS_WITH_VALUE = {
	"--after-context",
	"--before-context",
	"--context",
	"--encoding",
	"--file",
	"--glob",
	"--iglob",
	"--ignore-file",
	"--max-columns",
	"--max-count",
	"--max-depth",
	"--max-filesize",
	"--path-separator",
	"--pre",
	"--pre-glob",
	"--regexp",
	"--replace",
	"--sort",
	"--sortr",
	"--type",
	"--type-add",
	"--type-clear",
	"-A",
	"-B",
	"-C",
	"-E",
	"-M",
	"-T",
	"-e",
	"-f",
	"-g",
	"-m",
	"-r",
	"-t",
}
# Grep options that consume the following argument as a value.
GREP_OPTIONS_WITH_VALUE = {
	"--after-context",
	"--before-context",
	"--binary-files",
	"--context",
	"--directories",
	"--exclude",
	"--exclude-dir",
	"--exclude-from",
	"--file",
	"--include",
	"--label",
	"--max-count",
	"--regexp",
	"-A",
	"-B",
	"-C",
	"-D",
	"-d",
	"-e",
	"-f",
	"-m",
}
# Tree options that consume the following argument as a value.
TREE_OPTIONS_WITH_VALUE = {"--filelimit", "-I", "-L", "-P", "-o"}


def simple_commands(command: str) -> list[list[str]]:
	"""Split a shell command at control operators without executing it.

	Args:
		command: The shell command to split.

	Returns:
		Token groups for its simple commands, or an empty list if parsing fails.
	"""
	# Lexer that recognises shell control operators without running the command.
	lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|")
	lexer.commenters = ""
	lexer.whitespace_split = True
	# The tokens of each simple command found so far.
	commands: list[list[str]] = []
	# Tokens of the command being read, up to the next control operator.
	current: list[str] = []

	try:
		# Tokens parsed from the submitted shell command.
		tokens = list(lexer)
	except ValueError:
		return []

	# Current token being classified as an operator or command argument.
	for token in tokens:
		if token in COMMAND_SEPARATORS:
			if current:
				commands.append(current)
				current = []
			continue

		current.append(token)

	if current:
		commands.append(current)

	return commands


def positional_arguments(arguments: list[str], options_with_value: set[str]) -> list[str]:
	"""Collect positional arguments while skipping options and their values.

	Args:
		arguments: The arguments following a search executable.
		options_with_value: Options that consume the following argument.

	Returns:
		The positional pattern and path arguments.
	"""
	# Pattern and path arguments after options are removed.
	positionals: list[str] = []
	# Whether the preceding option consumes this argument.
	expect_value = False
	# Whether arguments may still be interpreted as options.
	options_enabled = True

	# Current search command argument.
	for argument in arguments:
		if expect_value:
			expect_value = False
			continue

		if options_enabled and argument == "--":
			options_enabled = False
			continue

		if options_enabled and argument in options_with_value:
			expect_value = True
			continue

		if options_enabled and argument.startswith("-") and argument != "-":
			continue

		positionals.append(argument)

	return positionals


def has_pattern_option(arguments: list[str]) -> bool:
	"""Check whether a search option supplies the pattern.

	Args:
		arguments: The arguments following a search executable.

	Returns:
		True when a pattern is supplied through an option rather than a positional argument.
	"""
	return any(
		argument in {"--regexp", "-e"}
		or argument.startswith("--regexp=")
		or (argument.startswith("-e") and len(argument) > 2)
		for argument in arguments
	)


def is_root_path(path: str) -> bool:
	"""Check whether a path names a broad search root.

	Args:
		path: The search path argument.

	Returns:
		True for a listed broad root or a path resolving to the filesystem root.
	"""
	return path in ROOT_PATHS or os.path.abspath(path) == "/"


def protected_directory(path: str) -> Optional[str]:
	"""Find the first protected directory named in a path.

	Args:
		path: The search path argument.

	Returns:
		The protected directory component, or None if none is present.
	"""
	# Non-empty path components checked against protected directory names.
	path_parts = [part for part in path.replace("\\", "/").split("/") if part not in {"", "."}]

	# Current path component being checked.
	for path_part in path_parts:
		if path_part in PROTECTED_DIRECTORIES:
			return path_part

	return None


def unsafe_path_reason(paths: list[str]) -> Optional[str]:
	"""Find why a recursive search path is too broad or protected.

	Args:
		paths: The paths the command searches recursively.

	Returns:
		A block reason when no path is given or a path is a broad root or protected directory, or None when all paths are safe.
	"""
	if not paths:
		return "the recursive search defaults to the repository root"

	# Current path supplied to the search command.
	for path in paths:
		if is_root_path(path):
			return f"the recursive search targets {path!r}"

		# Protected directory found within the current path, if any.
		blocked_directory = protected_directory(path)

		if blocked_directory:
			return f"the search enters protected directory {blocked_directory!r}"

	return None


def search_reason(executable: str, arguments: list[str], working_directory: Optional[str]) -> Optional[str]:
	"""Find why one search invocation must be blocked.

	Args:
		executable: The search executable basename.
		arguments: The arguments passed to the executable.
		working_directory: The directory selected by an earlier cd command, if any.

	Returns:
		A block reason for an unsafe search, or None when it is allowed.
	"""
	if working_directory:
		# Protected directory containing the selected working directory, if any.
		blocked_directory = protected_directory(working_directory)

		if blocked_directory:
			return f"the search runs inside protected directory {blocked_directory!r}"

	if executable == "rg":
		# Whether ripgrep was asked to bypass any ignore rules.
		bypasses_ignores = any(
			argument in {"--no-ignore", "--no-ignore-global", "--no-ignore-parent", "--no-ignore-vcs", "--unrestricted"}
			or re.fullmatch(r"-u{1,3}[A-Za-z]*", argument)
			for argument in arguments
		)

		if not bypasses_ignores:
			return None

		# Ripgrep arguments left after options and their values are removed.
		positionals = positional_arguments(arguments, RG_OPTIONS_WITH_VALUE)
		# Whether ripgrep lists files without a search pattern.
		files_only = "--files" in arguments
		# Explicit paths passed to ripgrep after any pattern is removed.
		paths = positionals if files_only or has_pattern_option(arguments) else positionals[1:]

		if not paths and working_directory and not is_root_path(working_directory):
			paths = [working_directory]

		return unsafe_path_reason(paths)

	if executable in {"grep", "egrep", "fgrep"}:
		# Whether grep searches directories recursively.
		recursive = any(
			argument in {"--recursive", "-R", "-r"}
			or (argument.startswith("-") and not argument.startswith("--") and ("R" in argument or "r" in argument))
			for argument in arguments
		)

		if not recursive:
			return None

		# Grep arguments left after options and their values are removed.
		positionals = positional_arguments(arguments, GREP_OPTIONS_WITH_VALUE)
		# Explicit paths passed to grep after any pattern is removed.
		paths = positionals if has_pattern_option(arguments) else positionals[1:]

		if not paths and working_directory and not is_root_path(working_directory):
			paths = [working_directory]

		return unsafe_path_reason(paths)

	if executable == "find":
		# Starting paths before the first find expression or option.
		paths = []

		# Current find argument being checked for the end of starting paths.
		for argument in arguments:
			if argument.startswith("-") or argument in {"!", "("}:
				break

			paths.append(argument)

		if not paths and working_directory and not is_root_path(working_directory):
			paths = [working_directory]

		return unsafe_path_reason(paths)

	if executable == "tree":
		# Explicit paths passed to tree after options are removed.
		paths = positional_arguments(arguments, TREE_OPTIONS_WITH_VALUE)

		if not paths and working_directory and not is_root_path(working_directory):
			paths = [working_directory]

		return unsafe_path_reason(paths)

	return None


def command_reason(command: str) -> Optional[str]:
	"""Find the first unsafe search in a complete shell command.

	Args:
		command: The shell command from the tool payload.

	Returns:
		The first block reason, or None when no unsafe search is found.
	"""
	# Directory selected by the most recent cd command, if any.
	working_directory: Optional[str] = None
	# Search program names recognised within each simple command.
	search_executables = {"egrep", "fgrep", "find", "grep", "rg", "tree"}

	# Tokens belonging to the current simple command.
	for command_tokens in simple_commands(command):
		if not command_tokens:
			continue

		if os.path.basename(command_tokens[0]) == "cd" and len(command_tokens) > 1:
			working_directory = command_tokens[1]
			continue

		# Position and text of a possible search executable.
		for index, token in enumerate(command_tokens):
			# Basename used to recognise a search executable with a path prefix.
			executable = os.path.basename(token)

			if executable not in search_executables:
				continue

			# Block reason returned for this search invocation, if any.
			reason = search_reason(executable, command_tokens[index + 1 :], working_directory)

			if reason:
				return reason

	return None


# First block reason found in the submitted shell command, if any.
reason = command_reason(sys.argv[1])

if reason:
	print(reason)
PY
}

# Denies the Bash tool call and tells the agent how to narrow it.
#
# @param  {string}  reason
#     Human-readable reason shown to the model.
block() {
	printf 'guard-search-boundaries: blocked: %s. Scope the search to a specific source or planning directory; use an exact file read for protected output.\n' "$1" >&2
	exit 2
}

# Block reason returned by the embedded search parser, if any.
reason="$(blocked_search_reason "$command_str")" || exit 0
[[ -n "$reason" ]] && block "$reason"

exit 0

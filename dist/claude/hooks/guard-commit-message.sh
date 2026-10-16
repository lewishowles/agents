#!/usr/bin/env bash
# Blocks an `hcom send` whose body proposes a commit message. Scout, Implementer,
# and Reviewer reports must not carry one: the Orchestrator writes the commit
# message for the human after review. A hit needs both a "commit message" mention
# and a Conventional Commit subject line, so packets that only say "omit the
# suggested commit message" pass through.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# Raw PreToolUse payload on stdin.
input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$command_str" ]] || exit 0

# Newlines flattened so patterns see one line (covers heredoc bodies).
normalised="${command_str//$'\n'/ }"

hcom_send_pattern='(^|[;&|`(]|[[:space:]])(command[[:space:]]+)?hcom[[:space:]]+send([[:space:]]|$)'
# The label an Implementer or Reviewer copies from the rules.
commit_mention_pattern='[Cc]ommit message'
# A Conventional Commit subject: `type:` or `type(scope):` followed by real text.
conventional_subject_pattern='(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]{1,40}\))?!?:[[:space:]]+[^[:space:]]'

if [[ "$normalised" =~ $hcom_send_pattern ]] \
	&& [[ "$normalised" =~ $commit_mention_pattern ]] \
	&& [[ "$normalised" =~ $conventional_subject_pattern ]]; then
	printf 'guard-commit-message: blocked: HCOM Scout, Implementer, and Reviewer reports do not carry a commit message. Report changed paths, verification, and blockers; the Orchestrator proposes the commit message to the human after review.\n' >&2
	exit 2
fi

exit 0

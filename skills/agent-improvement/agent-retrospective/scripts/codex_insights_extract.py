#!/usr/bin/env python3
"""Extract bounded behavioural evidence from Codex rollout JSONL files."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import shlex
import tempfile
from pathlib import Path
from typing import Iterable

CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
OUTPUT_PATH = CODEX_HOME / "usage-data/latest.json"
UTC = datetime.timezone.utc
SCHEMA_VERSION = "2.0.0"
SUPPORTED_RECORD_TYPES = {
	"event_msg",
	"response_item",
	"session_meta",
	"turn_context",
	"compacted",
}
TOOL_CALL_TYPES = {"custom_tool_call", "function_call"}
TOOL_RESULT_TYPES = {"custom_tool_call_output", "function_call_output"}
LIFECYCLE_EVENT_TYPES = {"task_complete", "thread_rolled_back", "turn_aborted"}
ACTIVITY_TERMINAL_EVENT_TYPES = {"task_complete", "turn_aborted"}
MAX_RECORD_BYTES = 256_000
MAX_EXCERPT_CHARS = 600
MAX_EVIDENCE_PER_ROLLOUT = 256
MAX_TOOL_EVENTS_PER_ROLLOUT = 96
MAX_CANDIDATES_PER_KIND = 32
CONFIG_TARGET_PATTERN = re.compile(
	r"(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json|hooks?[/\\]|scripts?[/\\])",
	re.IGNORECASE,
)
EXIT_CODE_PATTERN = re.compile(
	r"\b(?:exit(?:ed)?(?:\s+with)?(?:\s+code)?|exit[_\s]?code|return(?:ed)?|status[_\s]?code)\D{0,12}(-?\d+)\b",
	re.IGNORECASE,
)
# Phrasings that signal the user is correcting the agent. The "actually" branch
# requires a following article or pronoun so filler "actually" on its own does
# not match; the leading "no" branch is anchored so mid-sentence "no" is ignored.
CORRECTION_PATTERN = re.compile(
	r"(?:^no[,.!:]|\b(?:not what i asked|please stop|you (?:ignored|missed|should not)|"
	r"that(?:'s| is) wrong|do not |don't |instead of|i asked|i meant|"
	r"revert back to|roll back|undo that|undo the|(?:please )?try again|"
	r"actually,?\s+(?:it|the|that|this|i|we|you))\b)",
	re.IGNORECASE,
)
VERIFICATION_PATTERN = re.compile(
	r"\b(?:test|tests|lint|typecheck|validate|check)\b", re.IGNORECASE
)
APPROACH_CHANGE_PATTERN = re.compile(
	r"\b(?:instead|rather than|switch(?:ing)? to|change(?:d)? approach)\b",
	re.IGNORECASE,
)
EXPECTED_PROBE_PATTERN = re.compile(
	r"(?:^|\s)--(?:help|version)(?:\s|$)", re.IGNORECASE
)
CANDIDATE_KIND_NAMES = {
	"approach_changes": "approach_change",
	"configuration_touches": "configuration_touch",
	"corrections": "correction",
	"interruptions": "interruption",
	"retries": "retry",
	"rollbacks": "rollback",
	"verification": "verification",
}
# Tool names whose call arguments carry a shell command string.
SHELL_TOOL_NAMES = {"bash", "exec", "exec_command", "shell"}
# Tool names whose call arguments carry a file path to edit.
EDIT_TOOL_NAMES = {"apply_patch", "edit", "write"}
# Matches an apply_patch header line ("*** Add File: path", "*** Update File: path",
# "*** Delete File: path") to recover the edited path when it is not a separate argument.
PATCH_PATH_PATTERN = re.compile(
	r"^\*\*\* (?:Add|Delete|Update) File: (.+)$", re.MULTILINE
)
# Finds the real tool name in the harness's `tools.<name>(` call wrapper; payload.name
# is always the wrapper's own name ("exec"), never this one.
WRAPPED_TOOL_CALL_PATTERN = re.compile(r"tools\.([A-Za-z_][A-Za-z0-9_.]*)\(")
# Matches a bare identifier passed as a wrapped call's argument, when the harness built
# it as a variable beforehand instead of writing the value inline.
TOOL_ARGUMENT_REFERENCE_PATTERN = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)\b")
# Matches a const/let/var declaration that may hold the value for such an argument.
TOOL_ARGUMENT_DECLARATION_PATTERN = re.compile(
	r"\b(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
)


def parse_timestamp(value: object) -> datetime.datetime | None:
	"""Parse an ISO-8601 timestamp as a UTC datetime, or return null."""
	if not isinstance(value, str) or not value:
		return None

	try:
		parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
	except ValueError:
		return None

	if parsed.tzinfo is None:
		return None

	return parsed.astimezone(UTC)


def parse_bound(value: str) -> datetime.datetime:
	"""Parse one required command-line UTC bound."""
	timestamp = parse_timestamp(value)
	if timestamp is None:
		raise argparse.ArgumentTypeError(
			"expected an ISO-8601 UTC timestamp, for example 2026-08-09T00:00:00Z"
		)

	return timestamp


def format_timestamp(timestamp: datetime.datetime | None) -> str | None:
	"""Return one timestamp in canonical UTC JSON form, or null."""
	if timestamp is None:
		return None

	return timestamp.astimezone(UTC).isoformat().replace("+00:00", "Z")


def in_window(
	timestamp: datetime.datetime | None,
	start: datetime.datetime,
	end: datetime.datetime,
) -> bool:
	"""Return whether a timestamp is within the half-open UTC window."""
	return timestamp is not None and start <= timestamp < end


def bounded_text(value: object, limit: int = MAX_EXCERPT_CHARS) -> str | None:
	"""Return a bounded serialised value without treating it as trusted content."""
	if value is None:
		return None
	if isinstance(value, str):
		text = value
	else:
		try:
			text = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
		except (TypeError, ValueError):
			text = str(value)

	text = text.strip()
	if not text:
		return None

	return text[:limit]


def payload_for(record: dict[str, object]) -> dict[str, object]:
	"""Return a record payload object, or an empty object for unsupported shapes."""
	payload = record.get("payload")
	return payload if isinstance(payload, dict) else {}


def string_value(value: object) -> str | None:
	"""Return a non-empty string value, preserving missing values as null."""
	return value if isinstance(value, str) and value else None


def record_event_type(record: dict[str, object]) -> str:
	"""Return a nested event type when the payload explicitly declares one."""
	value = payload_for(record).get("type")
	return value if isinstance(value, str) else ""


def record_reference(rollout_id: str, record_index: int) -> str:
	"""Return a stable reference for one source-record position in a rollout."""
	return f"{rollout_id}:r{record_index:06d}"


def message_text(payload: dict[str, object]) -> str | None:
	"""Extract visible message text from a response item or authored event."""
	message = payload.get("message")
	if isinstance(message, str):
		return bounded_text(message)

	content = payload.get("content")
	if isinstance(content, str):
		return bounded_text(content)
	if not isinstance(content, list):
		return None

	parts = []
	for block in content:
		if isinstance(block, str):
			parts.append(block)
		elif isinstance(block, dict) and isinstance(block.get("text"), str):
			parts.append(block["text"])

	return bounded_text(" ".join(parts))


def is_authored_user_message(record: dict[str, object]) -> bool:
	"""Return whether a record is Codex's explicit authored-user event shape."""
	return (
		record.get("type") == "event_msg"
		and record_event_type(record) == "user_message"
	)


def response_user_fallback(record: dict[str, object]) -> bool:
	"""Return whether a response item is only an uncertain user-content fallback."""
	payload = payload_for(record)
	return (
		record.get("type") == "response_item"
		and payload.get("type") == "message"
		and payload.get("role") == "user"
	)


def is_activity_terminal_record(record: dict[str, object]) -> bool:
	"""Return whether one record ends activity for a live rollout."""
	return (
		record.get("type") in ACTIVITY_TERMINAL_EVENT_TYPES
		or record_event_type(record) in ACTIVITY_TERMINAL_EVENT_TYPES
	)


def status_from_value(value: object) -> str | None:
	"""Normalise explicit tool status without scanning arbitrary output wording."""
	if not isinstance(value, str):
		return None

	normalised = value.strip().casefold()
	if normalised in {"failed", "failure", "error", "errored", "cancelled", "canceled"}:
		return "failure"
	if normalised in {"success", "succeeded", "completed", "complete", "ok"}:
		return "success"
	return None


def explicit_error(payload: dict[str, object]) -> bool:
	"""Return whether a structured payload explicitly declares an error."""
	return payload.get("is_error") is True or payload.get("error") is True


def exit_code_from_value(value: object, depth: int = 0) -> int | None:
	"""Find a structured exit code in a shallow result value, or return null."""
	if depth > 3:
		return None
	if isinstance(value, dict):
		for key in (
			"exit_code",
			"exitCode",
			"returncode",
			"return_code",
			"status_code",
		):
			candidate = value.get(key)
			if isinstance(candidate, int) and not isinstance(candidate, bool):
				return candidate
		for child in value.values():
			candidate = exit_code_from_value(child, depth + 1)
			if candidate is not None:
				return candidate
	if isinstance(value, list):
		for child in value:
			candidate = exit_code_from_value(child, depth + 1)
			if candidate is not None:
				return candidate
	return None


def parsed_exit_code(value: object) -> int | None:
	"""Parse an explicit exit-code phrase, including zero, from bounded output."""
	text = bounded_text(value, MAX_RECORD_BYTES)
	if text is None:
		return None
	match = EXIT_CODE_PATTERN.search(text)
	return int(match.group(1)) if match is not None else None


def result_exit_code(result_payload: dict[str, object] | None) -> int | None:
	"""Return structured or explicitly reported result exit code without inferring status."""
	if result_payload is None:
		return None

	result_output = result_payload.get("output")
	for value in (result_output, result_payload):
		exit_code = exit_code_from_value(value)
		if exit_code is not None:
			return exit_code

	for value in (result_output, result_payload):
		exit_code = parsed_exit_code(value)
		if exit_code is not None:
			return exit_code

	return None


def tool_status(
	call_payload: dict[str, object], result_payload: dict[str, object] | None
) -> tuple[str, int | None, str]:
	"""Resolve tool status from structured error/status/exit evidence, else unknown."""
	result_output = None if result_payload is None else result_payload.get("output")
	exit_code = result_exit_code(result_payload)
	if result_payload is not None and explicit_error(result_payload):
		return "failure", exit_code, "explicit_error"
	if isinstance(result_output, dict) and explicit_error(result_output):
		return "failure", exit_code, "explicit_error"
	if explicit_error(call_payload):
		return "failure", exit_code, "explicit_error"

	for value, source in (
		(result_output, "structured_exit_code"),
		(result_payload, "structured_exit_code"),
	):
		structured_exit_code = exit_code_from_value(value)
		if structured_exit_code is not None:
			return (
				"success" if structured_exit_code == 0 else "failure",
				structured_exit_code,
				source,
			)

	result_output_status = (
		result_output.get("status") if isinstance(result_output, dict) else None
	)
	for value, source in (
		(result_output_status, "result_output_status"),
		(
			None if result_payload is None else result_payload.get("status"),
			"result_status",
		),
		(call_payload.get("status"), "call_status"),
	):
		status = status_from_value(value)
		if status is not None:
			return status, None, source

	for value, source in (
		(result_output, "parsed_exit_code"),
		(result_payload, "parsed_exit_code"),
	):
		parsed_code = parsed_exit_code(value)
		if parsed_code is not None:
			return "success" if parsed_code == 0 else "failure", parsed_code, source

	return "unknown", None, "unavailable"


def expected_probe_state(call_payload: dict[str, object], target: str | None) -> str:
	"""Return explicit or conservative candidate probe state for a tool event."""
	value = call_payload.get("expected_probe")
	if value is True:
		return "explicit"
	if value is False:
		return "not_expected"
	if target is not None and EXPECTED_PROBE_PATTERN.search(target):
		return "candidate"
	return "unavailable"


def call_target(payload: dict[str, object]) -> str | None:
	"""Return one bounded tool target from the explicitly recorded call input."""
	for key in ("input", "arguments", "name"):
		raw_value = payload.get(key)
		if isinstance(raw_value, str):
			try:
				parsed_value = json.loads(raw_value)
			except (TypeError, ValueError):
				parsed_value = None
			if isinstance(parsed_value, dict) and isinstance(
				parsed_value.get("command"), str
			):
				return bounded_text(parsed_value["command"], 280)
		value = bounded_text(raw_value, 280)
		if value is not None:
			return value
	return None


def unwrapped_tool_call(payload: dict[str, object]) -> tuple[str, object] | None:
	"""Return the real tool name and its decoded argument from a harness-wrapped call, resolving an inline literal directly or a bare identifier through its own declaration; null when neither resolves to one JSON value."""
	for key in ("input", "arguments"):
		value = payload.get(key)
		if not isinstance(value, str):
			continue

		matches = list(WRAPPED_TOOL_CALL_PATTERN.finditer(value))
		if len(matches) != 1:
			continue
		match = matches[0]

		argument_text = value[match.end() :].lstrip()
		if argument_text.startswith(('"', "{")):
			try:
				parsed_value, _ = json.JSONDecoder().raw_decode(value, match.end())
			except json.JSONDecodeError:
				continue

			return match.group(1), parsed_value

		argument_reference = TOOL_ARGUMENT_REFERENCE_PATTERN.match(value, match.end())
		if argument_reference is None:
			continue

		argument_name = argument_reference.group(1)
		for declaration in TOOL_ARGUMENT_DECLARATION_PATTERN.finditer(value):
			if declaration.group(1) != argument_name:
				continue

			try:
				parsed_value, value_end = json.JSONDecoder().raw_decode(
					value, declaration.end()
				)
			except json.JSONDecodeError:
				continue

			# A declaration followed by "+" is building the value from concatenation,
			# so the JSON literal alone is not the real argument; leave it unresolved.
			if value[value_end:].lstrip().startswith("+"):
				continue

			return match.group(1), parsed_value

	return None


def tool_structure(payload: dict[str, object]) -> dict[str, object]:
	"""Return the tool name plus a command argv, edit path, or skill name, each included only when the call arguments make it unambiguous."""
	tool_call = unwrapped_tool_call(payload)
	if tool_call is None:
		return {}

	tool_name, arguments = tool_call
	structure = {"tool": tool_name}

	if tool_name.casefold() in SHELL_TOOL_NAMES:
		if isinstance(arguments, dict):
			command = arguments.get("cmd")
			if isinstance(command, str) and command:
				try:
					argv = shlex.split(command)
				except ValueError:
					argv = []
				if argv:
					structure["command_argv"] = argv

	if tool_name.casefold() in EDIT_TOOL_NAMES:
		if isinstance(arguments, str):
			paths = set(PATCH_PATH_PATTERN.findall(arguments))
			if len(paths) == 1:
				structure["edit_path"] = paths.pop()

	if tool_name.casefold() == "skill":
		if isinstance(arguments, dict):
			skill_name = arguments.get("skill")
			if isinstance(skill_name, str) and skill_name:
				structure["skill_name"] = skill_name

	return structure


def candidate(kind: str, references: list[str], **details: object) -> dict[str, object]:
	"""Build one deterministic candidate that remains separate from semantic conclusions."""
	return {"kind": kind, "evidence_references": references, **details}


def hash_bytes(value: bytes) -> str:
	"""Return the SHA-256 digest for one byte sequence."""
	return hashlib.sha256(value).hexdigest()


def read_rollout(
	path: Path,
) -> tuple[list[dict[str, object]], int, str, list[dict[str, object]]]:
	"""Read supported JSONL records and bounded references for malformed records."""
	contents = path.read_bytes()
	malformed_count = 0
	malformed_records = []
	rollout_id = path.stem.removeprefix("rollout-")
	records = []
	for record_index, line in enumerate(contents.splitlines()):
		if not line:
			continue

		malformed_kind = None
		if len(line) > MAX_RECORD_BYTES:
			malformed_kind = "oversized_record"
		else:
			try:
				record = json.loads(line)
			except (TypeError, ValueError):
				malformed_kind = "invalid_json"
			else:
				if not isinstance(record, dict):
					malformed_kind = "unsupported_shape"
				elif record.get("type") not in SUPPORTED_RECORD_TYPES:
					malformed_kind = "unsupported_type"
				else:
					records.append(record)

		if malformed_kind is None:
			continue

		malformed_count += 1
		if len(malformed_records) < MAX_EVIDENCE_PER_ROLLOUT:
			malformed_records.append(
				{
					"reference": f"{rollout_id}:malformed:r{record_index:06d}",
					"rollout_id": rollout_id,
					"record_index": record_index,
					"kind": "malformed_record",
					"reason": malformed_kind,
				}
			)

	return records, malformed_count, hash_bytes(contents), malformed_records


def session_metadata(records: list[dict[str, object]]) -> dict[str, object]:
	"""Extract identity metadata without inferring links absent from Codex records."""
	metadata = {
		"conversation_id": None,
		"thread_source": None,
		"source_subagent": None,
		"subagent_parent_thread_id": None,
		"subagent_role": None,
		"project_path": None,
		"git": {"branch": None, "commit_hash": None, "repository_url": None},
	}
	for record in records:
		if record.get("type") not in {"session_meta", "turn_context"}:
			continue
		payload = payload_for(record)
		if metadata["conversation_id"] is None:
			metadata["conversation_id"] = string_value(payload.get("session_id"))
		if metadata["thread_source"] is None:
			metadata["thread_source"] = string_value(payload.get("thread_source"))
		source = payload.get("source")
		if metadata["source_subagent"] is None and isinstance(source, dict):
			subagent = source.get("subagent")
			if subagent is not None:
				metadata["source_subagent"] = subagent
		if isinstance(metadata["source_subagent"], dict):
			thread_spawn = metadata["source_subagent"].get("thread_spawn")
			if isinstance(thread_spawn, dict):
				if metadata["subagent_parent_thread_id"] is None:
					metadata["subagent_parent_thread_id"] = string_value(
						thread_spawn.get("parent_thread_id")
					)
				if metadata["subagent_role"] is None:
					metadata["subagent_role"] = string_value(
						thread_spawn.get("agent_role")
					)
		if metadata["project_path"] is None:
			metadata["project_path"] = string_value(payload.get("cwd"))
		git = payload.get("git")
		if isinstance(git, dict):
			for key in metadata["git"]:
				if metadata["git"][key] is None:
					metadata["git"][key] = string_value(git.get(key))

	return metadata


def is_delegated_rollout(metadata: dict[str, object]) -> bool:
	"""Return whether explicit thread-source or source-subagent provenance marks delegation."""
	return (
		metadata["thread_source"] == "subagent"
		or metadata["source_subagent"] is not None
	)


def extract_rollout(
	path: Path,
	start: datetime.datetime,
	end: datetime.datetime,
) -> tuple[dict[str, object] | None, dict[str, object]]:
	"""Extract bounded behavioural evidence for one rollout in a half-open UTC window."""
	rollout_id = path.stem.removeprefix("rollout-")
	records, malformed_count, source_hash, malformed_records = read_rollout(path)
	metadata = session_metadata(records)
	timestamps = [parse_timestamp(record.get("timestamp")) for record in records]
	valid_timestamps = sorted(
		timestamp for timestamp in timestamps if timestamp is not None
	)
	window_records = [
		(record_index, record, timestamp)
		for record_index, (record, timestamp) in enumerate(zip(records, timestamps))
		if in_window(timestamp, start, end)
	]
	source = {
		"path": path.as_posix(),
		"sha256": source_hash,
		"record_count": len(records),
		"malformed_record_count": malformed_count,
		"malformed_records": malformed_records,
	}
	if not window_records:
		return None, source

	evidence = []
	evidence_references = set()
	tool_ledger = []
	calls_by_id = {}
	authored_messages = []
	uncertain_user_messages = []
	assistant_messages = []
	candidates = {
		"approach_changes": [],
		"configuration_touches": [],
		"corrections": [],
		"interruptions": [],
		"retries": [],
		"rollbacks": [],
		"verification": [],
	}
	truncated = {"candidate_count": 0, "evidence_count": 0, "tool_event_count": 0}

	def add_evidence(entry: dict[str, object]) -> bool:
		"""Retain one evidence item only while the rollout bound permits it."""
		if len(evidence) >= MAX_EVIDENCE_PER_ROLLOUT:
			truncated["evidence_count"] += 1
			return False
		evidence.append(entry)
		evidence_references.add(entry["reference"])
		return True

	def add_candidate(kind: str, references: list[str], **details: object) -> None:
		"""Add a candidate only when its retained references and kind bound are valid."""
		if not all(reference in evidence_references for reference in references):
			truncated["candidate_count"] += 1
			return
		if len(candidates[kind]) >= MAX_CANDIDATES_PER_KIND:
			truncated["candidate_count"] += 1
			return
		candidates[kind].append(
			candidate(CANDIDATE_KIND_NAMES[kind], references, **details)
		)

	for record_index, record, timestamp in window_records:
		reference = record_reference(rollout_id, record_index)
		payload = payload_for(record)
		formatted_timestamp = format_timestamp(timestamp)
		if is_authored_user_message(record):
			text = message_text(payload)
			if text is None:
				continue
			entry = {
				"reference": reference,
				"timestamp": formatted_timestamp,
				"kind": "authored_user_message",
				"authorship": "authored",
				"excerpt": text,
			}
			if add_evidence(entry):
				authored_messages.append(entry)
				if CORRECTION_PATTERN.search(text):
					add_candidate(
						"corrections", [reference], source="authored_user_message"
					)
				if APPROACH_CHANGE_PATTERN.search(text):
					add_candidate(
						"approach_changes", [reference], source="authored_user_message"
					)
			continue

		if response_user_fallback(record):
			text = message_text(payload)
			if text is not None and add_evidence(
				{
					"reference": reference,
					"timestamp": formatted_timestamp,
					"kind": "uncertain_user_message",
					"authorship": "uncertain",
					"excerpt": text,
				}
			):
				uncertain_user_messages.append(reference)
			continue

		if (
			record.get("type") == "response_item"
			and payload.get("type") == "message"
			and payload.get("role") == "assistant"
		):
			text = message_text(payload)
			if text is not None and add_evidence(
				{
					"reference": reference,
					"timestamp": formatted_timestamp,
					"kind": "assistant_message",
					"excerpt": text,
				}
			):
				assistant_messages.append(reference)
			continue

		if (
			record.get("type") == "response_item"
			and payload.get("type") in TOOL_CALL_TYPES
		):
			if len(tool_ledger) >= MAX_TOOL_EVENTS_PER_ROLLOUT:
				truncated["tool_event_count"] += 1
				continue
			target = call_target(payload)
			structure = tool_structure(payload)
			if not add_evidence(
				{
					"reference": reference,
					"timestamp": formatted_timestamp,
					"kind": "tool_call",
					"tool_type": payload.get("type"),
					"target": target,
					**structure,
				}
			):
				continue
			call_id = string_value(payload.get("call_id")) or reference
			tool_ledger.append(
				{
					"call_id": call_id,
					"call_reference": reference,
					"result_reference": None,
					"timestamp": formatted_timestamp,
					"tool_type": payload.get("type"),
					"target": target,
					**structure,
					"status": "unknown",
					"status_source": "unavailable",
					"exit_code": None,
					"expected_probe": expected_probe_state(payload, target),
					"unmatched_call": True,
					"unmatched_result": False,
					"result_excerpt": None,
				}
			)
			calls_by_id[call_id] = (len(tool_ledger) - 1, payload)
			continue

		if (
			record.get("type") == "response_item"
			and payload.get("type") in TOOL_RESULT_TYPES
		):
			call_id = string_value(payload.get("call_id"))
			matched = calls_by_id.get(call_id or "")
			result_entry = {
				"reference": reference,
				"timestamp": formatted_timestamp,
				"kind": "tool_result",
				"tool_type": payload.get("type"),
				"excerpt": bounded_text(payload.get("output")),
			}
			if matched is not None:
				ledger_index, call_payload = matched
				retained_result = add_evidence(result_entry)
				entry = tool_ledger[ledger_index]
				status, exit_code, status_source = tool_status(call_payload, payload)
				entry.update(
					{
						"result_reference": reference if retained_result else None,
						"status": status,
						"status_source": status_source,
						"exit_code": exit_code,
						"unmatched_call": False,
						"result_excerpt": bounded_text(payload.get("output")),
					}
				)
				continue

			if len(tool_ledger) >= MAX_TOOL_EVENTS_PER_ROLLOUT:
				truncated["tool_event_count"] += 1
				continue
			if not add_evidence(result_entry):
				continue
			status, exit_code, status_source = tool_status({}, payload)
			tool_ledger.append(
				{
					"call_id": call_id,
					"call_reference": None,
					"result_reference": reference,
					"timestamp": formatted_timestamp,
					"tool_type": payload.get("type"),
					"target": None,
					"status": status,
					"status_source": status_source,
					"exit_code": exit_code,
					"expected_probe": "unavailable",
					"unmatched_call": False,
					"unmatched_result": True,
					"result_excerpt": bounded_text(payload.get("output")),
				}
			)
			continue

		event_type = record_event_type(record)
		if record.get("type") == "event_msg" and event_type in LIFECYCLE_EVENT_TYPES:
			evidence_kind = (
				"rollback_event"
				if event_type == "thread_rolled_back"
				else "lifecycle_event"
			)
			if add_evidence(
				{
					"reference": reference,
					"timestamp": formatted_timestamp,
					"kind": evidence_kind,
					"event_type": event_type,
				}
			):
				if event_type == "turn_aborted":
					add_candidate("interruptions", [reference], source="turn_aborted")
				if event_type == "thread_rolled_back":
					add_candidate("rollbacks", [reference], source="thread_rolled_back")

	for entry in tool_ledger:
		references = [
			reference
			for reference in (entry["call_reference"], entry["result_reference"])
			if reference is not None
		]
		target = entry["target"] if isinstance(entry["target"], str) else ""
		if entry["status"] == "failure" and entry["expected_probe"] != "explicit":
			add_candidate(
				"verification",
				references,
				source="failed_tool_event",
				status=entry["status"],
			)
		if VERIFICATION_PATTERN.search(target):
			add_candidate(
				"verification", references, source="tool_target", status=entry["status"]
			)
		if CONFIG_TARGET_PATTERN.search(target):
			add_candidate("configuration_touches", references, target=target)

	previous_by_target = {}
	for entry in tool_ledger:
		target = entry["target"]
		if not isinstance(target, str) or not target:
			continue
		previous = previous_by_target.get(target)
		if previous is not None and previous["status"] == "failure":
			references = [previous["call_reference"], entry["call_reference"]]
			if previous["result_reference"] is not None:
				references.append(previous["result_reference"])
			add_candidate("retries", references, target=target)
		previous_by_target[target] = entry

	last_record = records[-1] if records else None
	is_active = (
		last_record is not None
		and not is_activity_terminal_record(last_record)
		and "archived_sessions" not in path.parts
	)
	is_delegated = is_delegated_rollout(metadata)
	parent_thread_id = metadata["subagent_parent_thread_id"] if is_delegated else None
	role_state = "available" if metadata["subagent_role"] is not None else "unavailable"
	link_state = "available" if parent_thread_id is not None else "unavailable"
	if not is_delegated:
		role_state = "not_applicable"
		link_state = "not_applicable"

	unavailable = []
	if link_state == "unavailable":
		unavailable.append("subagent_parent_link")
	if role_state == "unavailable":
		unavailable.append("subagent_role")
	if not authored_messages:
		unavailable.append("no_authored_user_messages")
	return {
		"rollout_id": rollout_id,
		"conversation_id": metadata["conversation_id"],
		"conversation_id_state": "available"
		if metadata["conversation_id"] is not None
		else "unavailable",
		"thread_source": metadata["thread_source"],
		"delegation_state": "delegated" if is_delegated else "parent",
		"subagent_parent_thread_id": parent_thread_id,
		"subagent_role": metadata["subagent_role"],
		"subagent_link_state": link_state,
		"subagent_role_state": role_state,
		"project_path": metadata["project_path"],
		"git": metadata["git"],
		"start_timestamp": format_timestamp(valid_timestamps[0])
		if valid_timestamps
		else None,
		"end_timestamp": None
		if is_active
		else format_timestamp(valid_timestamps[-1])
		if valid_timestamps
		else None,
		"activity_state": "live" if is_active else "elapsed",
		"authored_user_message_count": len(authored_messages),
		"uncertain_user_message_references": uncertain_user_messages,
		"assistant_message_references": assistant_messages,
		"tool_ledger": tool_ledger,
		"evidence": evidence,
		"candidates": candidates,
		"truncation": truncated,
		"unavailable": unavailable,
	}, source


def build_report(
	paths: Iterable[Path],
	start: datetime.datetime,
	end: datetime.datetime,
) -> dict[str, object]:
	"""Build one deterministic extraction document for an exact half-open UTC window."""
	rollouts = []
	sources = []
	for path in sorted(paths, key=lambda item: item.as_posix()):
		rollout, source = extract_rollout(path, start, end)
		sources.append(source)
		if rollout is not None:
			rollouts.append(rollout)

	rollouts.sort(
		key=lambda rollout: (rollout["start_timestamp"] or "", rollout["rollout_id"])
	)
	conversation_ids = {
		rollout["conversation_id"]
		for rollout in rollouts
		if isinstance(rollout["conversation_id"], str)
	}
	subagent_rollouts = [
		rollout for rollout in rollouts if rollout["delegation_state"] == "delegated"
	]
	malformed_count = sum(source["malformed_record_count"] for source in sources)
	malformed_records = []
	for source in sources:
		for malformed_record in source["malformed_records"]:
			if len(malformed_records) >= MAX_EVIDENCE_PER_ROLLOUT:
				break
			malformed_records.append(
				{
					**malformed_record,
					"source_path": source["path"],
				}
			)
	if not sources:
		state = "unavailable"
	elif not rollouts:
		state = "empty"
	elif malformed_count:
		state = "partial"
	else:
		state = "available"
	activity_state = (
		"unavailable"
		if not rollouts
		else "live"
		if any(rollout["activity_state"] == "live" for rollout in rollouts)
		else "elapsed"
	)
	input_hashes = sorted(source["sha256"] for source in sources)
	input_sha256 = hash_bytes("\n".join(input_hashes).encode("utf-8"))
	return {
		"schema_version": SCHEMA_VERSION,
		"window": {
			"since": format_timestamp(start),
			"until": format_timestamp(end),
			"end_utc_exclusive": format_timestamp(end),
		},
		"bounds": {
			"max_excerpt_chars": MAX_EXCERPT_CHARS,
			"max_evidence_per_rollout": MAX_EVIDENCE_PER_ROLLOUT,
			"max_tool_events_per_rollout": MAX_TOOL_EVENTS_PER_ROLLOUT,
			"max_candidates_per_kind": MAX_CANDIDATES_PER_KIND,
			"max_record_bytes": MAX_RECORD_BYTES,
		},
		"provenance": {
			"input_sha256": input_sha256,
			"input_file_count": len(sources),
			"input_record_count": sum(source["record_count"] for source in sources),
			"malformed_record_count": malformed_count,
			"malformed_records": malformed_records,
			"source_hashes": input_hashes,
			"source_paths": sorted(source["path"] for source in sources),
		},
		"status": {"state": state, "activity_state": activity_state},
		"counts": {
			"rollout_count": len(rollouts),
			"conversation_count": len(conversation_ids),
			"conversation_id_unavailable_count": sum(
				rollout["conversation_id"] is None for rollout in rollouts
			),
			"subagent_rollout_count": len(subagent_rollouts),
			"subagent_role_unavailable_count": sum(
				rollout["subagent_role"] is None for rollout in subagent_rollouts
			),
		},
		"unavailable": (
			["no_rollout_files"]
			if not sources
			else ["no_selected_rollouts"]
			if not rollouts
			else []
		),
		"rollouts": rollouts,
	}


def serialise_report(report: dict[str, object]) -> str:
	"""Serialise one report with deterministic key ordering and indentation."""
	return json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def evidence_references_resolve(report: dict[str, object]) -> bool:
	"""Return whether every ledger and candidate reference resolves to retained evidence."""
	for rollout in report["rollouts"]:
		references = {entry["reference"] for entry in rollout["evidence"]}
		for ledger_entry in rollout["tool_ledger"]:
			for key in ("call_reference", "result_reference"):
				reference = ledger_entry[key]
				if reference is not None and reference not in references:
					return False
		for candidates in rollout["candidates"].values():
			for entry in candidates:
				if not all(
					reference in references
					for reference in entry["evidence_references"]
				):
					return False
	return True


def rollout_paths() -> list[Path]:
	"""Return Codex live and archived rollout files in deterministic path order."""
	paths = []
	for directory in (CODEX_HOME / "sessions", CODEX_HOME / "archived_sessions"):
		if directory.is_dir():
			paths.extend(path for path in directory.rglob("*.jsonl") if path.is_file())
	return sorted(set(paths), key=lambda path: path.as_posix())


def write_report(report: dict[str, object]) -> None:
	"""Write the extraction document to Codex's usage-data directory."""
	OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
	OUTPUT_PATH.write_text(serialise_report(report), encoding="utf-8")


def parse_arguments() -> argparse.Namespace:
	"""Parse the required time window or the isolated fixture self-test request."""
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--since", type=parse_bound)
	parser.add_argument("--until", type=parse_bound)
	parser.add_argument("--selftest", action="store_true")
	arguments = parser.parse_args()
	if arguments.selftest:
		if arguments.since is not None or arguments.until is not None:
			parser.error("--selftest cannot be combined with --since or --until")
		return arguments
	if arguments.since is None or arguments.until is None:
		parser.error("--since and --until must be provided together")
	if arguments.until < arguments.since:
		parser.error("--until must not be before --since")
	return arguments


def fixture_record(
	timestamp: str, record_kind: str, payload: dict[str, object]
) -> dict[str, object]:
	"""Wrap a fixture payload in the real timestamp/type/payload envelope."""
	return {"timestamp": timestamp, "type": record_kind, "payload": payload}


def write_fixture(
	path: Path, values: list[dict[str, object]], malformed: bool = False
) -> None:
	"""Write one representative JSONL rollout fixture."""
	lines = [json.dumps(value, sort_keys=True) for value in values]
	if malformed:
		lines[1:1] = [
			"not json",
			"x" * (MAX_RECORD_BYTES + 1),
			"[]",
			json.dumps({"type": "unsupported"}),
		]
	path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_selftest() -> None:
	"""Verify provenance, authorship, tool status and candidate bounds in isolation."""
	window_start = datetime.datetime(2026, 8, 8, 9, tzinfo=UTC)
	window_end = datetime.datetime(2026, 8, 8, 11, tzinfo=UTC)
	# Two real tool calls chained under one call_id, so unwrapped_tool_call() must treat
	# the tool identity as ambiguous rather than attribute the shared outcome to either.
	chained_tool_input = (
		'const patch = "*** Begin Patch\\n*** Update File: src/chained.py\\n*** End Patch"; '
		'await tools.apply_patch(patch); await tools.exec_command({"cmd": "validate"})'
	)
	with tempfile.TemporaryDirectory() as directory:
		root = Path(directory)
		parent = root / "rollout-parent.jsonl"
		subagent = root / "rollout-subagent.jsonl"
		write_fixture(
			parent,
			[
				fixture_record(
					"2026-08-08T10:00:00Z",
					"session_meta",
					{
						"id": "rollout-parent",
						"session_id": "conversation-1",
						"thread_source": "user",
						"cwd": "/tmp/project",
					},
				),
				fixture_record(
					"2026-08-08T10:01:00Z",
					"response_item",
					{
						"type": "message",
						"role": "developer",
						"content": "Injected AGENTS.md says do not use this approach instead.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:10Z",
					"response_item",
					{
						"type": "message",
						"role": "user",
						"content": "Please stop editing files.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:15Z",
					"event_msg",
					{
						"type": "user_message",
						"message": "I meant the other file.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:20Z",
					"event_msg",
					{
						"type": "user_message",
						"message": "That was not what I asked. Run validation instead.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:25Z",
					"event_msg",
					{
						"type": "user_message",
						"message": "No, that is the wrong file.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:27Z",
					"event_msg",
					{
						"type": "user_message",
						"message": "There is no rush on this.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:29Z",
					"event_msg",
					{
						"type": "user_message",
						"message": "Actually the tests pass now.",
					},
				),
				fixture_record(
					"2026-08-08T10:01:30Z",
					"response_item",
					{"type": "message", "role": "assistant", "content": "Understood."},
				),
				fixture_record(
					"2026-08-08T10:02:00Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "success",
						"name": "exec",
						"input": "validate",
					},
				),
				fixture_record(
					"2026-08-08T10:02:10Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "success",
						"output": "error word, Process exited with code 0",
					},
				),
				fixture_record(
					"2026-08-08T10:02:20Z",
					"response_item",
					{
						"type": "function_call",
						"call_id": "failure",
						"name": "exec",
						"arguments": 'const command = {"cmd": "validate"}; await tools.exec_command(command)',
					},
				),
				fixture_record(
					"2026-08-08T10:02:30Z",
					"response_item",
					{
						"type": "function_call_output",
						"call_id": "failure",
						"output": {"exit_code": 1},
					},
				),
				fixture_record(
					"2026-08-08T10:02:40Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "retry",
						"name": "exec",
						"input": 'const command = {"cmd": "validate"}; await tools.exec_command(command)',
					},
				),
				fixture_record(
					"2026-08-08T10:02:50Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "retry",
						"output": {"status": "success"},
					},
				),
				fixture_record(
					"2026-08-08T10:03:00Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "unknown",
						"name": "exec",
						"input": "scripts/run.sh",
					},
				),
				fixture_record(
					"2026-08-08T10:03:10Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "missing",
						"output": "validation error text only",
					},
				),
				fixture_record(
					"2026-08-08T10:03:20Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "config",
						"name": "exec",
						"input": "cat AGENTS.md",
					},
				),
				fixture_record(
					"2026-08-08T10:03:30Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "edit",
						"name": "exec",
						"input": 'const patch = "*** Begin Patch\\n*** Update File: src/example.py\\n*** End Patch"; await tools.apply_patch(patch)',
					},
				),
				fixture_record(
					"2026-08-08T10:03:35Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "edit",
						"output": {"status": "success"},
					},
				),
				fixture_record(
					"2026-08-08T10:03:40Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "skill",
						"name": "exec",
						"input": 'const r = await tools.Skill({"skill": "code-style"})',
					},
				),
				fixture_record(
					"2026-08-08T10:03:45Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "skill",
						"output": {"status": "success"},
					},
				),
				fixture_record(
					"2026-08-08T10:03:50Z",
					"response_item",
					{
						"type": "custom_tool_call",
						"call_id": "chained",
						"name": "exec",
						"input": chained_tool_input,
					},
				),
				fixture_record(
					"2026-08-08T10:03:55Z",
					"response_item",
					{
						"type": "custom_tool_call_output",
						"call_id": "chained",
						"output": {"status": "success"},
					},
				),
				fixture_record(
					"2026-08-08T10:04:00Z",
					"event_msg",
					{
						"type": "task_complete",
						"turn_id": "turn-complete",
						"last_agent_message": "Finished.",
						"completed_at": 1786269840,
					},
				),
				fixture_record(
					"2026-08-08T10:04:10Z",
					"event_msg",
					{
						"type": "turn_aborted",
						"turn_id": "turn-aborted",
						"reason": "interrupted",
						"completed_at": 1786269850,
					},
				),
				fixture_record(
					"2026-08-08T10:04:20Z",
					"event_msg",
					{"type": "thread_rolled_back", "num_turns": 1},
				),
			],
			malformed=True,
		)
		write_fixture(
			subagent,
			[
				fixture_record(
					"2026-08-08T10:00:00Z",
					"session_meta",
					{
						"id": "rollout-subagent",
						"session_id": "conversation-1",
						"thread_source": "subagent",
						"source": {
							"subagent": {
								"thread_spawn": {
									"parent_thread_id": "conversation-1",
									"depth": 1,
									"agent_path": "/root/scout",
									"agent_nickname": "Scout",
									"agent_role": None,
								}
							}
						},
					},
				),
				fixture_record(
					"2026-08-08T10:01:00Z", "event_msg", {"type": "task_complete"}
				),
			],
		)
		source_only = root / "rollout-source-only.jsonl"
		write_fixture(
			source_only,
			[
				fixture_record(
					"2026-08-08T10:00:00Z",
					"session_meta",
					{
						"id": "rollout-source-only",
						"session_id": "conversation-2",
						"source": {"subagent": {"other": "guardian"}},
					},
				),
				fixture_record(
					"2026-08-08T10:01:00Z",
					"event_msg",
					{
						"type": "task_complete",
						"turn_id": "source-only-complete",
						"last_agent_message": "Finished.",
						"completed_at": 1786269660,
					},
				),
			],
		)
		bounded = root / "rollout-bounded.jsonl"
		bounded_records = [
			fixture_record(
				"2026-08-08T10:00:00Z",
				"session_meta",
				{
					"id": "rollout-bounded",
					"session_id": "conversation-bounded",
					"thread_source": "user",
				},
			)
		]
		for index in range(MAX_TOOL_EVENTS_PER_ROLLOUT):
			call_id = f"bound-{index}"
			bounded_records.extend(
				[
					fixture_record(
						"2026-08-08T10:01:00Z",
						"response_item",
						{
							"type": "custom_tool_call",
							"call_id": call_id,
							"name": "exec",
							"input": json.dumps({"command": f"check {index}"}),
						},
					),
					fixture_record(
						"2026-08-08T10:01:10Z",
						"response_item",
						{
							"type": "custom_tool_call_output",
							"call_id": call_id,
							"output": {"status": "success"},
						},
					),
				]
			)
		bounded_records.append(
			fixture_record(
				"2026-08-08T10:01:20Z",
				"response_item",
				{
					"type": "custom_tool_call_output",
					"call_id": "unmatched-overflow",
					"output": {"status": "failure"},
				},
			)
		)
		write_fixture(bounded, bounded_records)

		first = build_report([parent, subagent], window_start, window_end)
		second = build_report([subagent, parent], window_start, window_end)
		assert serialise_report(first) == serialise_report(second)
		assert first["schema_version"] == SCHEMA_VERSION
		assert first["status"] == {"state": "partial", "activity_state": "live"}
		assert first["counts"] == {
			"rollout_count": 2,
			"conversation_count": 1,
			"conversation_id_unavailable_count": 0,
			"subagent_rollout_count": 1,
			"subagent_role_unavailable_count": 1,
		}
		assert first["provenance"]["source_paths"] == sorted(
			[parent.as_posix(), subagent.as_posix()]
		)
		assert first["provenance"]["malformed_record_count"] == 4
		assert first["provenance"]["malformed_records"] == [
			{
				"kind": "malformed_record",
				"reason": "invalid_json",
				"record_index": 1,
				"reference": "parent:malformed:r000001",
				"rollout_id": "parent",
				"source_path": parent.as_posix(),
			},
			{
				"kind": "malformed_record",
				"reason": "oversized_record",
				"record_index": 2,
				"reference": "parent:malformed:r000002",
				"rollout_id": "parent",
				"source_path": parent.as_posix(),
			},
			{
				"kind": "malformed_record",
				"reason": "unsupported_shape",
				"record_index": 3,
				"reference": "parent:malformed:r000003",
				"rollout_id": "parent",
				"source_path": parent.as_posix(),
			},
			{
				"kind": "malformed_record",
				"reason": "unsupported_type",
				"record_index": 4,
				"reference": "parent:malformed:r000004",
				"rollout_id": "parent",
				"source_path": parent.as_posix(),
			},
		]
		assert evidence_references_resolve(first)
		parent_rollout = next(
			rollout
			for rollout in first["rollouts"]
			if rollout["rollout_id"] == "parent"
		)
		assert parent_rollout["conversation_id"] == "conversation-1"
		assert parent_rollout["delegation_state"] == "parent"
		assert parent_rollout["subagent_role"] is None
		assert parent_rollout["subagent_link_state"] == "not_applicable"
		assert parent_rollout["subagent_role_state"] == "not_applicable"
		assert parent_rollout["activity_state"] == "live"
		assert parent_rollout["end_timestamp"] is None
		assert parent_rollout["authored_user_message_count"] == 5
		assert len(parent_rollout["uncertain_user_message_references"]) == 1
		assert len(parent_rollout["candidates"]["corrections"]) == 4
		assert all(
			"Injected AGENTS.md says do not use this approach instead."
			not in entry.get("excerpt", "")
			for entry in parent_rollout["evidence"]
		)
		ledger = {entry["call_id"]: entry for entry in parent_rollout["tool_ledger"]}
		assert ledger["success"]["status"] == "success"
		assert ledger["success"]["exit_code"] == 0
		assert ledger["failure"]["status"] == "failure"
		assert ledger["failure"]["exit_code"] == 1
		assert ledger["failure"]["command_argv"] == ["validate"]
		assert ledger["retry"]["status"] == "success"
		assert ledger["unknown"]["status"] == "unknown"
		assert ledger["missing"]["unmatched_result"] is True
		assert ledger["config"]["unmatched_call"] is True
		assert ledger["edit"]["edit_path"] == "src/example.py"
		assert ledger["skill"]["skill_name"] == "code-style"
		assert ledger["chained"]["target"] == chained_tool_input
		assert all(
			key not in ledger["chained"]
			for key in ("tool", "command_argv", "edit_path", "skill_name")
		)
		assert len(parent_rollout["candidates"]["retries"]) == 1
		assert parent_rollout["candidates"]["retries"][0]["kind"] == "retry"
		assert len(parent_rollout["candidates"]["verification"]) >= 1
		assert any(
			entry.get("target") == "cat AGENTS.md"
			for entry in parent_rollout["candidates"]["configuration_touches"]
		)
		assert len(parent_rollout["candidates"]["interruptions"]) == 1
		assert len(parent_rollout["candidates"]["rollbacks"]) == 1
		assert [
			(entry["kind"], entry["event_type"])
			for entry in parent_rollout["evidence"]
			if entry["kind"] in {"lifecycle_event", "rollback_event"}
		] == [
			("lifecycle_event", "task_complete"),
			("lifecycle_event", "turn_aborted"),
			("rollback_event", "thread_rolled_back"),
		]
		subagent_rollout = next(
			rollout
			for rollout in first["rollouts"]
			if rollout["rollout_id"] == "subagent"
		)
		assert subagent_rollout["delegation_state"] == "delegated"
		assert subagent_rollout["subagent_parent_thread_id"] == "conversation-1"
		assert subagent_rollout["subagent_link_state"] == "available"
		assert subagent_rollout["subagent_role"] is None
		assert subagent_rollout["subagent_role_state"] == "unavailable"
		assert first["provenance"]["input_file_count"] == 2
		source_only_report = build_report([source_only], window_start, window_end)
		source_only_rollout = source_only_report["rollouts"][0]
		assert source_only_rollout["delegation_state"] == "delegated"
		assert source_only_rollout["subagent_link_state"] == "unavailable"
		assert source_only_rollout["subagent_role_state"] == "unavailable"
		empty_report = build_report(
			[parent],
			datetime.datetime(2026, 8, 8, 11, tzinfo=UTC),
			datetime.datetime(2026, 8, 8, 12, tzinfo=UTC),
		)
		assert empty_report["status"] == {
			"state": "empty",
			"activity_state": "unavailable",
		}
		assert empty_report["unavailable"] == ["no_selected_rollouts"]
		assert build_report([], window_start, window_end)["status"] == {
			"state": "unavailable",
			"activity_state": "unavailable",
		}
		bounded_report = build_report([bounded], window_start, window_end)
		bounded_ledger = bounded_report["rollouts"][0]["tool_ledger"]
		assert len(bounded_ledger) == MAX_TOOL_EVENTS_PER_ROLLOUT
		assert all(entry["result_reference"] is not None for entry in bounded_ledger)
		assert all(entry["status"] == "success" for entry in bounded_ledger)
		assert bounded_report["rollouts"][0]["truncation"]["tool_event_count"] == 1
		assert evidence_references_resolve(bounded_report)
		assert tool_status(
			{}, {"is_error": True, "output": {"exit_code": 0, "status": "success"}}
		) == (
			"failure",
			0,
			"explicit_error",
		)
		assert tool_status({}, {"output": {"exit_code": 1, "status": "success"}}) == (
			"failure",
			1,
			"structured_exit_code",
		)
		assert tool_status(
			{}, {"status": "success", "output": "Process exited with code 1"}
		) == (
			"success",
			None,
			"result_status",
		)
		assert tool_status(
			{}, {"status": "failure", "output": "Process exited with code 0"}
		) == (
			"failure",
			None,
			"result_status",
		)

	print("codex_insights_extract selftest passed")


def main() -> None:
	"""Run the isolated self-test or write a real bounded extraction report."""
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return

	report = build_report(rollout_paths(), arguments.since, arguments.until)
	write_report(report)
	print(
		f"Wrote {report['counts']['rollout_count']} rollouts to {OUTPUT_PATH} "
		f"(state={report['status']['state']})"
	)


if __name__ == "__main__":
	main()

#!/usr/bin/env python3
"""Constants and shared helpers for validating and classifying bounded Codex evidence."""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Iterable

# The configured Codex directory, or the user's default Codex directory.
CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
# The directory holding extracted usage reports and their derived documents.
USAGE_DATA_DIRECTORY = CODEX_HOME / "usage-data"
# The default source document for facet generation.
DEFAULT_EXTRACTION_PATH = USAGE_DATA_DIRECTORY / "latest.json"
# The default destination for conversation facets.
DEFAULT_FACETS_PATH = USAGE_DATA_DIRECTORY / "latest-facets.json"
# The default destination for the written findings.
DEFAULT_NARRATIVE_PATH = USAGE_DATA_DIRECTORY / "latest-narrative.json"
# The timezone used when normalising evidence timestamps.
UTC = datetime.timezone.utc
# The extraction schema accepted by the facet builder.
EXTRACTION_SCHEMA_VERSION = "2.0.0"
# The schema written for conversation facets.
FACETS_SCHEMA_VERSION = "1.0.0"
# The schema written for the narrative findings.
NARRATIVE_SCHEMA_VERSION = "2.0.0"
# The most characters retained from one evidence excerpt.
MAX_EXCERPT_CHARS = 600
# The maximum number of turns retained from one rollout.
MAX_TURNS_PER_ROLLOUT = 32
# The maximum number of events retained for one conversation.
MAX_EVENTS_PER_CONVERSATION = 96
# The maximum number of limitations reported for one conversation.
MAX_LIMITATIONS_PER_CONVERSATION = 16
# The maximum number of observations considered for repeated patterns.
MAX_PATTERN_OBSERVATIONS = 512
# The maximum number of citations retained for one pattern.
MAX_PATTERN_CITATIONS = 16
# The maximum number of evidence links retained in one citation.
MAX_EVIDENCE_REFERENCES_PER_CITATION = 8
# The maximum number of findings written to the narrative.
MAX_FINDINGS = 64
# The largest configuration file, in bytes, that is checked; larger files are reported
# as unavailable.
MAX_CONFIGURATION_BYTES = 64 * 1024
# Matches paths that point to project instructions, skills, hooks or scripts.
CONFIGURATION_SURFACE_PATTERN = re.compile(
	r"(?:^|[/\\.])(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)"
	r"$|(?:^|[/\\])(?:hooks?|scripts?)(?:[/\\]|$)",
	re.IGNORECASE,
)
# Finds those same configuration surfaces within a longer command or path.
CONFIGURATION_TOKEN_PATTERN = re.compile(
	r"(?:^|[/\\])(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)(?:$|[/\\])"
	r"|(?:^|[/\\])(?:hooks?|scripts?)(?:[/\\]|$)",
	re.IGNORECASE,
)
# Matches a configuration file name without a directory path.
CONFIGURATION_BASENAME_PATTERN = re.compile(
	r"^(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)$",
	re.IGNORECASE,
)
# Ordered action-label rules for one observation's descriptor. The first pattern that
# matches the observation kind, tool names and command arguments wins. The rules are
# skipped when an entry records an edit path or a skill name.
DESCRIPTOR_ACTION_RULES = (
	(re.compile(r"\b(?:pytest|unittest|vitest)\b", re.IGNORECASE), "run unit tests"),
	(re.compile(r"\b(?:ruff|eslint|flake8|pylint)\b", re.IGNORECASE), "run lint"),
	(re.compile(r"\bhcom\s+send\b", re.IGNORECASE), "send hcom message"),
	(
		re.compile(r"\b(?:exec|exec_command|bash|shell)\b", re.IGNORECASE),
		"run command",
	),
)

# Maps extraction candidate fields to the pattern kind used by the renderer.
CANDIDATE_FIELDS = {
	"approach_changes": "approach_change",
	"configuration_touches": "configuration_touch",
	"corrections": "correction",
	"interruptions": "interruption",
	"retries": "retry",
	"rollbacks": "rollback",
	# Not a plain singular ("verification"): must match the PATTERN_KINDS entry below,
	# or the renderer drops matching findings silently.
	"verification": "verification_gap",
}
# The kinds of observations that can form repeated patterns.
PATTERN_KINDS = (
	"approach_change",
	"configuration_touch",
	"correction",
	"interruption",
	"retry",
	"rollback",
	"tool_failure",
	"verification_gap",
	"recovery",
)


class ProvenanceError(ValueError):
	"""Raised when a bounded artefact is stale, malformed, or not traceable."""


def parse_timestamp(value: object) -> datetime.datetime | None:
	"""Parse an ISO-8601 timestamp with a timezone into UTC.

	Args:
		value: The timestamp text to parse.

	Returns:
		The UTC datetime, or None when the value is missing or invalid.
	"""
	if not isinstance(value, str) or not value:
		return None

	try:
		# The parsed timestamp before timezone validation and UTC conversion.
		parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
	except ValueError:
		return None

	if parsed.tzinfo is None:
		return None

	return parsed.astimezone(UTC)


def format_timestamp(value: object) -> str | None:
	"""Format a valid timestamp as canonical UTC text.

	Args:
		value: The timestamp to normalise.

	Returns:
		The UTC timestamp, or None when the value is missing or invalid.
	"""
	# The parsed timestamp used for canonical formatting.
	parsed = parse_timestamp(value)
	if parsed is None:
		return None

	return parsed.isoformat().replace("+00:00", "Z")


def bounded_text(value: object, limit: int = MAX_EXCERPT_CHARS) -> str | None:
	"""Return a value as trimmed text cut to limit characters.

	A value that is not a string is written as JSON first.

	Args:
		value: The value to render as text.
		limit: The maximum number of characters to keep.

	Returns:
		The shortened text, or None for an empty or missing value.
	"""
	if value is None:
		return None
	# The source text, serialised first when the input is not a string.
	if isinstance(value, str):
		text = value
	else:
		try:
			text = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
		except (TypeError, ValueError):
			text = str(value)

	text = text.strip()
	return text[:limit] if text else None


def descriptor_for_entries(
	kind: str,
	entries: Iterable[dict[str, object]],
	repo: object,
	status: object = None,
) -> dict[str, object]:
	"""Describe one candidate or ledger observation using its tool entries.

	When the entries point to no single target, the target type and value are None.

	Args:
		kind: The observation kind, searched with the tool text for an action and used
			to mark retries as fail_then_pass.
		entries: The tool ledger entries supporting the observation.
		repo: The repository path to include in the descriptor.
		status: The observed success or failure, when known.

	Returns:
		The action, tool, target, repository and outcome for the observation.
	"""
	# The entries kept in order for target and command inspection.
	entry_values = list(entries)
	# The distinct non-empty tool names recorded on these entries.
	tools = {
		entry["tool"]
		for entry in entry_values
		if isinstance(entry.get("tool"), str) and entry["tool"]
	}
	# The tool name when every entry with a name agrees.
	tool = next(iter(tools)) if len(tools) == 1 else None
	# The string command arguments used to identify the action.
	command_arguments = []
	# Whether an entry identifies a file edit.
	has_edit_path = False
	# Whether an entry identifies a skill use.
	has_skill_name = False
	# Note any file edit or skill use, and collect each command's text arguments.
	for entry in entry_values:
		has_edit_path = has_edit_path or isinstance(entry.get("edit_path"), str)
		has_skill_name = has_skill_name or isinstance(entry.get("skill_name"), str)

		# The argument list, when the entry records a command.
		command_argv = entry.get("command_argv")
		if not isinstance(command_argv, list):
			continue
		# Only the text arguments of the command are kept.
		command_arguments.extend(
			argument for argument in command_argv if isinstance(argument, str)
		)
	# The kind, tool names and command arguments searched for a known action.
	action_text = " ".join(
		[
			kind,
			*(value for value in tools),
			*command_arguments,
		]
	)
	# The most specific action supported by the entries.
	if has_edit_path:
		action = "edit file"
	elif has_skill_name:
		action = "use skill"
	else:
		# Each rule supplies a pattern and a label for the observed action.
		action = next(
			(
				label
				for pattern, label in DESCRIPTOR_ACTION_RULES
				if pattern.search(action_text)
			),
			"record event",
		)
	# Distinct file, skill and failed executable targets from the entries.
	targets = set()
	for entry in entry_values:
		# A file path targeted by an edit command.
		edit_path = entry.get("edit_path")
		if isinstance(edit_path, str) and edit_path:
			targets.add(("file", edit_path))

		# A skill invoked by the tool entry.
		skill_name = entry.get("skill_name")
		if isinstance(skill_name, str) and skill_name:
			targets.add(("skill", skill_name))

		# Only a failed command earns an executable target, taken from its first argument;
		# a passing command is not friction to attribute to a binary.
		command_argv = entry.get("command_argv")
		if (
			entry.get("status") == "failure"
			and isinstance(command_argv, list)
			and command_argv
			and isinstance(command_argv[0], str)
			and command_argv[0]
		):
			targets.add(("executable", command_argv[0]))
	# The single unambiguous target, if the evidence identifies one.
	if len(targets) == 1:
		target_type, target_value = next(iter(targets))
	else:
		target_type, target_value = None, None

	# The outcome category attached to this kind and status.
	if kind == "retry":
		outcome = "fail_then_pass"
	elif status == "success":
		outcome = "pass"
	elif status == "failure":
		outcome = "fail"
	else:
		outcome = "unknown"

	return {
		"action": action,
		"tool": tool,
		"target": {"type": target_type, "value": target_value},
		"repo": bounded_text(repo, 280),
		"outcome": outcome,
	}


def hash_bytes(value: bytes) -> str:
	"""Hash bytes to bind downstream documents to their exact input.

	Args:
		value: The bytes to hash.

	Returns:
		The SHA-256 hexadecimal digest.
	"""
	return hashlib.sha256(value).hexdigest()


def serialise(value: dict[str, object]) -> str:
	"""Serialise a generated document with stable key ordering.

	Args:
		value: The document to serialise.

	Returns:
		Indented JSON text ending in a newline.
	"""
	return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def require_mapping(value: object, location: str) -> dict[str, object]:
	"""Require one JSON object at a schema location.

	Args:
		value: The value to check.
		location: The schema location named in an error.

	Returns:
		The validated JSON object.

	Raises:
		ProvenanceError: The value is not an object.
	"""
	if not isinstance(value, dict):
		raise ProvenanceError(f"{location} must be an object")

	return value


def require_string(value: object, location: str) -> str:
	"""Require one non-empty string at a schema location.

	Args:
		value: The value to check.
		location: The schema location named in an error.

	Returns:
		The validated string.

	Raises:
		ProvenanceError: The value is not a non-empty string.
	"""
	if not isinstance(value, str) or not value:
		raise ProvenanceError(f"{location} must be a non-empty string")

	return value


def require_count(value: object, location: str) -> int:
	"""Require one non-negative integer count.

	Args:
		value: The value to check.
		location: The schema location named in an error.

	Returns:
		The validated count.

	Raises:
		ProvenanceError: The value is not a non-negative integer.
	"""
	if not isinstance(value, int) or isinstance(value, bool) or value < 0:
		raise ProvenanceError(f"{location} must be a non-negative integer")

	return value


def load_json(path: Path) -> dict[str, object]:
	"""Read one JSON object from disk with a clear input failure.

	Args:
		path: The JSON file to read.

	Returns:
		The parsed JSON object.

	Raises:
		ProvenanceError: The file cannot be read or does not contain an object.
	"""
	try:
		# The parsed file content before the root object check.
		value = json.loads(path.read_text(encoding="utf-8"))
	except (OSError, UnicodeError, json.JSONDecodeError) as error:
		raise ProvenanceError(f"cannot read JSON artefact {path}: {error}") from error

	return require_mapping(value, str(path))


def extraction_provenance(
	extraction: dict[str, object], extraction_path: Path, extraction_sha256: str
) -> dict[str, object]:
	"""Build the extraction binding copied into downstream documents.

	Args:
		extraction: The validated source extraction.
		extraction_path: The path to the source extraction.
		extraction_sha256: The digest of the source extraction bytes.

	Returns:
		The source path, schema, hashes, window and counts for provenance checks.

	Raises:
		ProvenanceError: A required extraction field is absent or invalid.
	"""
	# The extraction period copied into the binding.
	window = require_mapping(extraction.get("window"), "extraction.window")
	# The source counts copied into the binding.
	counts = require_mapping(extraction.get("counts"), "extraction.counts")
	# The original input hashes copied into the binding.
	provenance = require_mapping(extraction.get("provenance"), "extraction.provenance")
	return {
		"extraction_path": extraction_path.as_posix(),
		"extraction_schema_version": extraction["schema_version"],
		"extraction_sha256": extraction_sha256,
		"input_sha256": require_string(
			provenance.get("input_sha256"), "extraction.provenance.input_sha256"
		),
		"source_hashes": list(provenance.get("source_hashes", [])),
		"window": {
			"since": window.get("since"),
			"until": window.get("until"),
			"end_utc_exclusive": window.get("end_utc_exclusive"),
		},
		"counts": dict(counts),
	}


def evidence_reference_index(
	extraction: dict[str, object],
) -> tuple[dict[str, dict[str, object]], dict[str, dict[str, object]]]:
	"""Index retained evidence and rollouts and reject dangling references.

	Args:
		extraction: The source extraction to index.

	Returns:
		The evidence index and rollout index, both keyed by their references.

	Raises:
		ProvenanceError: A rollout, ledger entry or evidence link is invalid.
	"""
	# Evidence records keyed by their unique reference.
	evidence_index: dict[str, dict[str, object]] = {}
	# Rollout records keyed by their unique ID.
	rollout_index: dict[str, dict[str, object]] = {}
	# The source rollouts whose evidence and links will be checked.
	rollouts = extraction.get("rollouts")
	if not isinstance(rollouts, list):
		raise ProvenanceError("extraction.rollouts must be an array")

	# Each source rollout must have a unique ID and valid evidence links.
	for rollout_value in rollouts:
		# The current rollout, checked to be an object.
		rollout = require_mapping(rollout_value, "extraction.rollouts[]")
		# The rollout's ID, which must not repeat.
		rollout_id = require_string(rollout.get("rollout_id"), "rollout.rollout_id")
		if rollout_id in rollout_index:
			raise ProvenanceError(f"duplicate rollout ID: {rollout_id}")

		rollout_index[rollout_id] = rollout
		# The evidence records retained in this rollout.
		evidence = rollout.get("evidence")
		if not isinstance(evidence, list):
			raise ProvenanceError(f"rollout {rollout_id} evidence must be an array")

		# Each evidence record must have a reference no other record uses.
		for evidence_value in evidence:
			# The current evidence record, checked to be an object.
			entry = require_mapping(evidence_value, f"rollout {rollout_id}.evidence[]")
			# The reference used by candidate and ledger links.
			reference = require_string(entry.get("reference"), "evidence.reference")
			if reference in evidence_index:
				raise ProvenanceError(f"duplicate evidence reference: {reference}")

			evidence_index[reference] = {
				**entry,
				"conversation_id": rollout.get("conversation_id"),
				"rollout_id": rollout_id,
			}

		# Each candidate field can contain references to retained evidence.
		for field_name in CANDIDATE_FIELDS:
			# Candidate observations in this field.
			candidates = rollout.get("candidates", {}).get(field_name, [])
			if not isinstance(candidates, list):
				raise ProvenanceError(
					f"rollout {rollout_id}.candidates.{field_name} must be an array"
				)
			# Each candidate must refer only to indexed evidence.
			for candidate in candidates:
				# The current candidate, checked to be an object.
				candidate_value = require_mapping(
					candidate, f"rollout {rollout_id}.{field_name}[]"
				)
				validate_references(
					candidate_value.get("evidence_references"),
					evidence_index,
					field_name,
				)

		# Tool calls and results whose references must also resolve.
		ledger = rollout.get("tool_ledger", [])
		if not isinstance(ledger, list):
			raise ProvenanceError(f"rollout {rollout_id}.tool_ledger must be an array")
		# Each ledger entry may link to a call and a result.
		for ledger_value in ledger:
			# The current ledger entry, checked to be an object.
			ledger_entry = require_mapping(
				ledger_value, f"rollout {rollout_id}.tool_ledger[]"
			)
			# Both possible ledger references must point to retained evidence.
			for field_name in ("call_reference", "result_reference"):
				# The evidence reference stored in this ledger field.
				reference = ledger_entry.get(field_name)
				if reference is not None:
					validate_references([reference], evidence_index, field_name)

	return evidence_index, rollout_index


def validate_references(
	references: object, evidence_index: dict[str, dict[str, object]], location: str
) -> list[str]:
	"""Require every evidence reference to resolve to retained evidence.

	Args:
		references: The list of evidence references to check.
		evidence_index: The retained evidence keyed by reference.
		location: The source field named in an error.

	Returns:
		The checked references in their original order.

	Raises:
		ProvenanceError: The list is invalid or a reference is missing.
	"""
	if not isinstance(references, list):
		raise ProvenanceError(f"{location}.evidence_references must be an array")

	# The references that have resolved to retained evidence.
	validated = []
	# Each reference must be a string naming retained evidence.
	for reference in references:
		if not isinstance(reference, str) or reference not in evidence_index:
			raise ProvenanceError(
				f"{location} contains dangling evidence reference: {reference!r}"
			)
		validated.append(reference)

	return validated


def validate_extraction(path: Path) -> dict[str, object]:
	"""Validate the extraction schema, counts and retained evidence links.

	Args:
		path: The extraction file to validate.

	Returns:
		The document, source path, hash, indexes and downstream binding.

	Raises:
		ProvenanceError: The file cannot be read or its contents are inconsistent.
	"""
	try:
		# The file bytes whose hash binds the downstream documents to this extraction.
		contents = path.read_bytes()
	except OSError as error:
		raise ProvenanceError(
			f"cannot read extraction artefact {path}: {error}"
		) from error

	# The parsed source document after its root object check.
	extraction = load_json(path)
	if extraction.get("schema_version") != EXTRACTION_SCHEMA_VERSION:
		raise ProvenanceError(
			f"unsupported extraction schema {extraction.get('schema_version')!r}; "
			f"expected {EXTRACTION_SCHEMA_VERSION}"
		)

	# The extraction period, whose timestamps must all be valid UTC.
	window = require_mapping(extraction.get("window"), "extraction.window")
	# Each required timestamp must resolve to UTC.
	for field_name in ("since", "until", "end_utc_exclusive"):
		if format_timestamp(window.get(field_name)) is None:
			raise ProvenanceError(
				f"extraction.window.{field_name} is not a UTC timestamp"
			)
	if window["until"] != window["end_utc_exclusive"]:
		raise ProvenanceError("extraction.window.end_utc_exclusive must equal until")
	if parse_timestamp(window["until"]) <= parse_timestamp(window["since"]):
		raise ProvenanceError(
			"extraction window must be half-open with until after since"
		)

	# The source hashes used to trace extraction to its inputs.
	provenance = require_mapping(extraction.get("provenance"), "extraction.provenance")
	require_string(provenance.get("input_sha256"), "extraction.provenance.input_sha256")
	# The source hash list checked for string values.
	source_hashes = provenance.get("source_hashes")
	# Each hash in the list must be text.
	if not isinstance(source_hashes, list) or not all(
		isinstance(value, str) for value in source_hashes
	):
		raise ProvenanceError(
			"extraction.provenance.source_hashes must be a string array"
		)

	# The declared totals checked against the retained rollouts.
	counts = require_mapping(extraction.get("counts"), "extraction.counts")
	# Each declared total must be a valid count.
	for field_name in (
		"rollout_count",
		"conversation_count",
		"subagent_rollout_count",
		"conversation_id_unavailable_count",
		"subagent_role_unavailable_count",
	):
		require_count(counts.get(field_name), f"extraction.counts.{field_name}")

	# The validated indexes used by later facet builders.
	evidence_index, rollout_index = evidence_reference_index(extraction)
	# The retained rollouts used to recompute declared totals.
	rollouts = list(rollout_index.values())
	# The distinct non-empty conversation IDs across the rollouts.
	conversation_ids = {
		rollout.get("conversation_id")
		for rollout in rollouts
		if isinstance(rollout.get("conversation_id"), str)
		and rollout.get("conversation_id")
	}
	# The number of rollouts marked as delegated.
	subagent_count = sum(
		rollout.get("delegation_state") == "delegated" for rollout in rollouts
	)
	# The number of rollouts without a conversation ID.
	conversation_unavailable_count = sum(
		rollout.get("conversation_id") is None for rollout in rollouts
	)
	# The number of delegated rollouts without a recorded role.
	role_unavailable_count = sum(
		rollout.get("delegation_state") == "delegated"
		and rollout.get("subagent_role") is None
		for rollout in rollouts
	)
	# Totals recomputed from the retained rollout data.
	expected_counts = {
		"rollout_count": len(rollouts),
		"conversation_count": len(conversation_ids),
		"subagent_rollout_count": subagent_count,
		"conversation_id_unavailable_count": conversation_unavailable_count,
		"subagent_role_unavailable_count": role_unavailable_count,
	}
	# Each declared total must match its recomputed value.
	for field_name, expected in expected_counts.items():
		if counts[field_name] != expected:
			raise ProvenanceError(
				f"extraction.counts.{field_name} does not match retained rollouts: "
				f"{counts[field_name]} != {expected}"
			)

	return {
		"document": extraction,
		"path": path,
		"sha256": hash_bytes(contents),
		"evidence_index": evidence_index,
		"rollout_index": rollout_index,
		"binding": extraction_provenance(extraction, path, hash_bytes(contents)),
	}


def conversation_key(rollout: dict[str, object]) -> str:
	"""Group rollouts by conversation while isolating missing identities.

	Args:
		rollout: The source rollout whose conversation is being grouped.

	Returns:
		The conversation ID, or a rollout-specific key when it is unavailable.
	"""
	# The explicit conversation ID, when Codex supplied one.
	conversation_id = rollout.get("conversation_id")
	if isinstance(conversation_id, str) and conversation_id:
		return conversation_id

	return f"unavailable:{rollout.get('rollout_id')}"


def available_conversation_id(rollout: dict[str, object]) -> str | None:
	"""Return a conversation ID only when Codex supplied one explicitly.

	Args:
		rollout: The source rollout to inspect.

	Returns:
		The conversation ID, or None when none is available.
	"""
	# The source value checked before exposing it as an ID.
	conversation_id = rollout.get("conversation_id")
	return (
		conversation_id
		if isinstance(conversation_id, str) and conversation_id
		else None
	)


def references_for_entries(entries: Iterable[dict[str, object]]) -> list[str]:
	"""Collect unique evidence references in source order.

	Args:
		entries: The observations containing evidence links.

	Returns:
		The first occurrence of each evidence reference.
	"""
	# The ordered references kept for the derived observation.
	references = []
	# References already added to the ordered result.
	seen = set()
	# Each observation can carry several evidence links.
	for entry in entries:
		# Evidence links within the current observation.
		for reference in entry.get("evidence_references", []):
			if reference not in seen:
				seen.add(reference)
				references.append(reference)

	return references


def earliest_timestamp(
	entries: Iterable[dict[str, object]], evidence_index: dict[str, dict[str, object]]
) -> str | None:
	"""Find the earliest retained timestamp supporting one derived event.

	Args:
		entries: The observations containing evidence links.
		evidence_index: The retained evidence keyed by reference.

	Returns:
		The earliest timestamp in UTC, or None when none is available.
	"""
	# Valid timestamps found through the observations' evidence links.
	timestamps = []
	# Each observation can contribute several timestamps.
	for entry in entries:
		# Evidence links within the current observation.
		for reference in entry.get("evidence_references", []):
			# The parsed time of the referenced evidence, when available.
			timestamp = parse_timestamp(evidence_index[reference].get("timestamp"))
			if timestamp is not None:
				timestamps.append(timestamp)

	return format_timestamp(min(timestamps).isoformat()) if timestamps else None


def descriptor_pattern_key(descriptor: object) -> str:
	"""Build the grouping key for one observation from its structured descriptor.

	The key joins action, target type, target value and repo with "|" so that two
	observations of the same behaviour group together wherever the checkout lived.
	File targets become repo-relative and an absolute repo path collapses to its
	directory name, so a temp-directory checkout and a permanent one produce the
	same key. A relative repo path is kept whole. Missing parts are written as
	"null" rather than dropped, which keeps the key shape fixed. A recovery
	descriptor always carries the friction kind it recovered from as a final
	"source" part, so recoveries from different friction kinds stay apart.

	Args:
		descriptor: The structured observation descriptor.

	Returns:
		A stable key for the action, target and repository, with a recovery source
		when one is available.
	"""
	# The descriptor object, or an empty one for malformed input.
	descriptor = descriptor if isinstance(descriptor, dict) else {}
	# The action label to normalise for grouping.
	action = descriptor.get("action")
	# The normalised action, or None when the descriptor has none.
	if isinstance(action, str) and action.strip():
		action_value = " ".join(action.casefold().split())
	else:
		action_value = None

	# The structured target information, when present.
	target = descriptor.get("target")
	# The target kind and value, or missing values for an invalid target.
	if isinstance(target, dict):
		target_type = target.get("type")
		target_value = target.get("value")
	else:
		target_type = None
		target_value = None
	if target_type not in {"file", "executable", "skill", "repo", "hcom_peer"}:
		target_type = None
	if not isinstance(target_value, str) or not target_value.strip():
		target_value = None

	# The repository path text retained with the observation.
	repo_text = descriptor.get("repo")
	# A path object used to compare the repository with file targets.
	repo_path = Path(repo_text) if isinstance(repo_text, str) and repo_text else None
	# The repository name or relative path used in the grouping key.
	if repo_path is not None and repo_path.is_absolute():
		repo_key = repo_path.name or repo_path.anchor
	elif repo_path is not None:
		repo_key = repo_path.as_posix()
	else:
		repo_key = None

	if target_type == "file" and target_value:
		# The file target normalised against the observed repository.
		target_path = Path(target_value)
		if (
			target_path.is_absolute()
			and repo_path is not None
			and repo_path.is_absolute()
		):
			try:
				target_value = target_path.relative_to(repo_path).as_posix()
			except ValueError:
				target_value = target_path.as_posix()
		elif not target_path.is_absolute():
			target_value = target_path.as_posix()

	# The action, target type, target value and repository, with "null" for any
	# missing value.
	key_parts = [
		action_value or "null",
		target_type or "null",
		target_value or "null",
		repo_key or "null",
	]
	# The friction source appended when the descriptor records recovery.
	source = descriptor.get("source")
	if isinstance(source, str) and source.strip():
		key_parts.append(" ".join(source.casefold().split()))

	return "|".join(key_parts)


def event_classification(kind: str, status: object = None) -> dict[str, object]:
	"""Label an event's cause using fixed rules, not a model's judgement.

	Args:
		kind: The observed event kind.
		status: The source event status to preserve in the result.

	Returns:
		The cause label, the rule-based method, the model set to None, the given status
		and a confidence level.
	"""
	# The cause label assigned to this event kind.
	if kind in {"correction", "tool_failure"}:
		label = "agent_failure" if kind == "correction" else "workflow_failure"
	elif kind == "recovery":
		label = "workflow_recovery"
	elif kind in {"interruption", "rollback", "verification_gap"}:
		label = "workflow_failure"
	else:
		label = "mixed_causes"

	# Confidence based on how directly the event identifies its cause.
	confidence = (
		"high" if kind in {"correction", "tool_failure", "recovery"} else "medium"
	)
	return {
		"label": label,
		"method": "deterministic_candidate",
		"model": None,
		"status": status,
		"confidence": confidence,
	}

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

CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
USAGE_DATA_DIRECTORY = CODEX_HOME / "usage-data"
DEFAULT_EXTRACTION_PATH = USAGE_DATA_DIRECTORY / "latest.json"
DEFAULT_FACETS_PATH = USAGE_DATA_DIRECTORY / "latest-facets.json"
DEFAULT_NARRATIVE_PATH = USAGE_DATA_DIRECTORY / "latest-narrative.json"
UTC = datetime.timezone.utc
EXTRACTION_SCHEMA_VERSION = "2.0.0"
FACETS_SCHEMA_VERSION = "1.0.0"
NARRATIVE_SCHEMA_VERSION = "2.0.0"
MAX_EXCERPT_CHARS = 600
MAX_TURNS_PER_ROLLOUT = 32
MAX_EVENTS_PER_CONVERSATION = 96
MAX_LIMITATIONS_PER_CONVERSATION = 16
MAX_PATTERN_OBSERVATIONS = 512
MAX_PATTERN_CITATIONS = 16
MAX_EVIDENCE_REFERENCES_PER_CITATION = 8
MAX_FINDINGS = 64
MAX_CONFIGURATION_BYTES = 64 * 1024
CONFIGURATION_SURFACE_PATTERN = re.compile(
	r"(?:^|[/\\.])(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)"
	r"$|(?:^|[/\\])(?:hooks?|scripts?)(?:[/\\]|$)",
	re.IGNORECASE,
)
CONFIGURATION_TOKEN_PATTERN = re.compile(
	r"(?:^|[/\\])(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)(?:$|[/\\])"
	r"|(?:^|[/\\])(?:hooks?|scripts?)(?:[/\\]|$)",
	re.IGNORECASE,
)
CONFIGURATION_BASENAME_PATTERN = re.compile(
	r"^(?:AGENTS\.md|WORKSPACE\.md|SKILL(?:\.body)?\.md|skill\.json)$",
	re.IGNORECASE,
)
# Ordered action-label rules for one observation's descriptor; the first pattern that
# matches the observation's tool, target executable, and command text wins.
DESCRIPTOR_ACTION_RULES = (
	(re.compile(r"\b(?:pytest|unittest|vitest)\b", re.IGNORECASE), "run unit tests"),
	(re.compile(r"\b(?:ruff|eslint|flake8|pylint)\b", re.IGNORECASE), "run lint"),
	(re.compile(r"\bhcom\s+send\b", re.IGNORECASE), "send hcom message"),
	(
		re.compile(r"\b(?:exec|exec_command|bash|shell)\b", re.IGNORECASE),
		"run command",
	),
)

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
PATTERN_KINDS = (
	"approach_change",
	"configuration_touch",
	"correction",
	"interruption",
	"retry",
	"rollback",
	"tool_failure",
	"verification_gap",
	"successful_behaviour",
)


class ProvenanceError(ValueError):
	"""Raised when a bounded artefact is stale, malformed, or not traceable."""


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


def format_timestamp(value: object) -> str | None:
	"""Return a canonical UTC timestamp, or null for unavailable evidence."""
	parsed = parse_timestamp(value)
	if parsed is None:
		return None

	return parsed.isoformat().replace("+00:00", "Z")


def bounded_text(value: object, limit: int = MAX_EXCERPT_CHARS) -> str | None:
	"""Truncate to `limit` characters; collapse empty or missing values to None."""
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
	return text[:limit] if text else None


def descriptor_for_entries(
	kind: str,
	entries: Iterable[dict[str, object]],
	repo: object,
	status: object = None,
) -> dict[str, object]:
	"""Build the action/tool/target/repo/outcome descriptor for one candidate or ledger observation from its tool-ledger entries, leaving target null when its type or value is not structurally unambiguous."""
	entry_values = list(entries)
	tools = {
		entry["tool"]
		for entry in entry_values
		if isinstance(entry.get("tool"), str) and entry["tool"]
	}
	tool = next(iter(tools)) if len(tools) == 1 else None
	command_arguments = []
	has_edit_path = False
	has_skill_name = False
	for entry in entry_values:
		has_edit_path = has_edit_path or isinstance(entry.get("edit_path"), str)
		has_skill_name = has_skill_name or isinstance(entry.get("skill_name"), str)

		command_argv = entry.get("command_argv")
		if not isinstance(command_argv, list):
			continue
		command_arguments.extend(
			argument for argument in command_argv if isinstance(argument, str)
		)
	action_text = " ".join(
		[
			kind,
			*(value for value in tools),
			*command_arguments,
		]
	)
	if has_edit_path:
		action = "edit file"
	elif has_skill_name:
		action = "use skill"
	else:
		action = next(
			(
				label
				for pattern, label in DESCRIPTOR_ACTION_RULES
				if pattern.search(action_text)
			),
			"record event",
		)
	targets = set()
	for entry in entry_values:
		edit_path = entry.get("edit_path")
		if isinstance(edit_path, str) and edit_path:
			targets.add(("file", edit_path))

		skill_name = entry.get("skill_name")
		if isinstance(skill_name, str) and skill_name:
			targets.add(("skill", skill_name))

		# A command only earns an executable target when it failed: a passing command
		# is not friction worth attributing to a specific binary.
		command_argv = entry.get("command_argv")
		if (
			entry.get("status") == "failure"
			and isinstance(command_argv, list)
			and command_argv
			and isinstance(command_argv[0], str)
			and command_argv[0]
		):
			targets.add(("executable", command_argv[0]))
	if len(targets) == 1:
		target_type, target_value = next(iter(targets))
	else:
		target_type, target_value = None, None

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
	"""Return the SHA-256 digest for one byte sequence."""
	return hashlib.sha256(value).hexdigest()


def serialise(value: dict[str, object]) -> str:
	"""Serialise a generated document with stable key ordering."""
	return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def require_mapping(value: object, location: str) -> dict[str, object]:
	"""Require one JSON object at a schema location."""
	if not isinstance(value, dict):
		raise ProvenanceError(f"{location} must be an object")

	return value


def require_string(value: object, location: str) -> str:
	"""Require one non-empty string at a schema location."""
	if not isinstance(value, str) or not value:
		raise ProvenanceError(f"{location} must be a non-empty string")

	return value


def require_count(value: object, location: str) -> int:
	"""Require one non-negative integer count."""
	if not isinstance(value, int) or isinstance(value, bool) or value < 0:
		raise ProvenanceError(f"{location} must be a non-negative integer")

	return value


def load_json(path: Path) -> dict[str, object]:
	"""Read one JSON object from disk, preserving a clear input failure."""
	try:
		value = json.loads(path.read_text(encoding="utf-8"))
	except (OSError, UnicodeError, json.JSONDecodeError) as error:
		raise ProvenanceError(f"cannot read JSON artefact {path}: {error}") from error

	return require_mapping(value, str(path))


def extraction_provenance(
	extraction: dict[str, object], extraction_path: Path, extraction_sha256: str
) -> dict[str, object]:
	"""Return the exact Commit 1 binding copied into downstream artefacts."""
	window = require_mapping(extraction.get("window"), "extraction.window")
	counts = require_mapping(extraction.get("counts"), "extraction.counts")
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
	"""Index retained evidence and rollouts while rejecting dangling references."""
	evidence_index: dict[str, dict[str, object]] = {}
	rollout_index: dict[str, dict[str, object]] = {}
	rollouts = extraction.get("rollouts")
	if not isinstance(rollouts, list):
		raise ProvenanceError("extraction.rollouts must be an array")

	for rollout_value in rollouts:
		rollout = require_mapping(rollout_value, "extraction.rollouts[]")
		rollout_id = require_string(rollout.get("rollout_id"), "rollout.rollout_id")
		if rollout_id in rollout_index:
			raise ProvenanceError(f"duplicate rollout ID: {rollout_id}")

		rollout_index[rollout_id] = rollout
		evidence = rollout.get("evidence")
		if not isinstance(evidence, list):
			raise ProvenanceError(f"rollout {rollout_id} evidence must be an array")

		for evidence_value in evidence:
			entry = require_mapping(evidence_value, f"rollout {rollout_id}.evidence[]")
			reference = require_string(entry.get("reference"), "evidence.reference")
			if reference in evidence_index:
				raise ProvenanceError(f"duplicate evidence reference: {reference}")

			evidence_index[reference] = {
				**entry,
				"conversation_id": rollout.get("conversation_id"),
				"rollout_id": rollout_id,
			}

		for field_name in CANDIDATE_FIELDS:
			candidates = rollout.get("candidates", {}).get(field_name, [])
			if not isinstance(candidates, list):
				raise ProvenanceError(
					f"rollout {rollout_id}.candidates.{field_name} must be an array"
				)
			for candidate in candidates:
				candidate_value = require_mapping(
					candidate, f"rollout {rollout_id}.{field_name}[]"
				)
				validate_references(
					candidate_value.get("evidence_references"),
					evidence_index,
					field_name,
				)

		ledger = rollout.get("tool_ledger", [])
		if not isinstance(ledger, list):
			raise ProvenanceError(f"rollout {rollout_id}.tool_ledger must be an array")
		for ledger_value in ledger:
			ledger_entry = require_mapping(
				ledger_value, f"rollout {rollout_id}.tool_ledger[]"
			)
			for field_name in ("call_reference", "result_reference"):
				reference = ledger_entry.get(field_name)
				if reference is not None:
					validate_references([reference], evidence_index, field_name)

	return evidence_index, rollout_index


def validate_references(
	references: object, evidence_index: dict[str, dict[str, object]], location: str
) -> list[str]:
	"""Require every evidence reference to resolve to retained extraction evidence."""
	if not isinstance(references, list):
		raise ProvenanceError(f"{location}.evidence_references must be an array")

	validated = []
	for reference in references:
		if not isinstance(reference, str) or reference not in evidence_index:
			raise ProvenanceError(
				f"{location} contains dangling evidence reference: {reference!r}"
			)
		validated.append(reference)

	return validated


def validate_extraction(path: Path) -> dict[str, object]:
	"""Validate the Commit 1 schema, counts, and all retained evidence links."""
	try:
		contents = path.read_bytes()
	except OSError as error:
		raise ProvenanceError(
			f"cannot read extraction artefact {path}: {error}"
		) from error

	extraction = load_json(path)
	if extraction.get("schema_version") != EXTRACTION_SCHEMA_VERSION:
		raise ProvenanceError(
			f"unsupported extraction schema {extraction.get('schema_version')!r}; "
			f"expected {EXTRACTION_SCHEMA_VERSION}"
		)

	window = require_mapping(extraction.get("window"), "extraction.window")
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

	provenance = require_mapping(extraction.get("provenance"), "extraction.provenance")
	require_string(provenance.get("input_sha256"), "extraction.provenance.input_sha256")
	source_hashes = provenance.get("source_hashes")
	if not isinstance(source_hashes, list) or not all(
		isinstance(value, str) for value in source_hashes
	):
		raise ProvenanceError(
			"extraction.provenance.source_hashes must be a string array"
		)

	counts = require_mapping(extraction.get("counts"), "extraction.counts")
	for field_name in (
		"rollout_count",
		"conversation_count",
		"subagent_rollout_count",
		"conversation_id_unavailable_count",
		"subagent_role_unavailable_count",
	):
		require_count(counts.get(field_name), f"extraction.counts.{field_name}")

	evidence_index, rollout_index = evidence_reference_index(extraction)
	rollouts = list(rollout_index.values())
	conversation_ids = {
		rollout.get("conversation_id")
		for rollout in rollouts
		if isinstance(rollout.get("conversation_id"), str)
		and rollout.get("conversation_id")
	}
	subagent_count = sum(
		rollout.get("delegation_state") == "delegated" for rollout in rollouts
	)
	conversation_unavailable_count = sum(
		rollout.get("conversation_id") is None for rollout in rollouts
	)
	role_unavailable_count = sum(
		rollout.get("delegation_state") == "delegated"
		and rollout.get("subagent_role") is None
		for rollout in rollouts
	)
	expected_counts = {
		"rollout_count": len(rollouts),
		"conversation_count": len(conversation_ids),
		"subagent_rollout_count": subagent_count,
		"conversation_id_unavailable_count": conversation_unavailable_count,
		"subagent_role_unavailable_count": role_unavailable_count,
	}
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
	"""Return a unique grouping key, isolating rollouts without conversation identity."""
	conversation_id = rollout.get("conversation_id")
	if isinstance(conversation_id, str) and conversation_id:
		return conversation_id

	return f"unavailable:{rollout.get('rollout_id')}"


def available_conversation_id(rollout: dict[str, object]) -> str | None:
	"""Return a conversation ID only when Codex supplied one explicitly."""
	conversation_id = rollout.get("conversation_id")
	return (
		conversation_id
		if isinstance(conversation_id, str) and conversation_id
		else None
	)


def references_for_entries(entries: Iterable[dict[str, object]]) -> list[str]:
	"""Return unique evidence references in source order."""
	references = []
	seen = set()
	for entry in entries:
		for reference in entry.get("evidence_references", []):
			if reference not in seen:
				seen.add(reference)
				references.append(reference)

	return references


def earliest_timestamp(
	entries: Iterable[dict[str, object]], evidence_index: dict[str, dict[str, object]]
) -> str | None:
	"""Return the earliest retained timestamp supporting one derived event."""
	timestamps = []
	for entry in entries:
		for reference in entry.get("evidence_references", []):
			timestamp = parse_timestamp(evidence_index[reference].get("timestamp"))
			if timestamp is not None:
				timestamps.append(timestamp)

	return format_timestamp(min(timestamps)) if timestamps else None


def descriptor_pattern_key(descriptor: object) -> str:
	"""Build the grouping key for one observation from its structured descriptor.

	The key joins action, target type, target value and repo with "|" so that two
	observations of the same behaviour group together wherever the checkout lived.
	File targets become repo-relative and the repo collapses to its directory name,
	so a temp-directory checkout and a permanent one produce the same key. Missing
	parts are written as "null" rather than dropped, which keeps the key shape fixed.
	"""
	descriptor = descriptor if isinstance(descriptor, dict) else {}
	action = descriptor.get("action")
	if isinstance(action, str) and action.strip():
		action_value = " ".join(action.casefold().split())
	else:
		action_value = None

	target = descriptor.get("target")
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

	repo_text = descriptor.get("repo")
	repo_path = Path(repo_text) if isinstance(repo_text, str) and repo_text else None
	if repo_path is not None and repo_path.is_absolute():
		repo_key = repo_path.name or repo_path.anchor
	elif repo_path is not None:
		repo_key = repo_path.as_posix()
	else:
		repo_key = None

	if target_type == "file" and target_value:
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

	return "|".join(
		(
			action_value or "null",
			target_type or "null",
			target_value or "null",
			repo_key or "null",
		)
	)


def event_classification(kind: str, status: object = None) -> dict[str, object]:
	"""Classify deterministic evidence without presenting it as a model conclusion."""
	if kind in {"correction", "tool_failure"}:
		label = "agent_failure" if kind == "correction" else "workflow_failure"
	elif kind == "successful_behaviour":
		label = "successful_behaviour"
	elif kind in {"interruption", "rollback", "verification_gap"}:
		label = "workflow_failure"
	else:
		label = "mixed_causes"

	confidence = (
		"high"
		if kind in {"correction", "tool_failure", "successful_behaviour"}
		else "medium"
	)
	return {
		"label": label,
		"method": "deterministic_candidate",
		"model": None,
		"status": status,
		"confidence": confidence,
	}

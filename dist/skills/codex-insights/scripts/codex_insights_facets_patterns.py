#!/usr/bin/env python3
"""Build configuration patterns and per-pattern status from Codex observations."""

from __future__ import annotations

import shlex
from pathlib import Path
from typing import Iterable

from codex_insights_facets_common import (
	CONFIGURATION_BASENAME_PATTERN,
	CONFIGURATION_TOKEN_PATTERN,
	MAX_CONFIGURATION_BYTES,
	MAX_EVIDENCE_REFERENCES_PER_CITATION,
	MAX_PATTERN_CITATIONS,
	MAX_PATTERN_OBSERVATIONS,
	descriptor_pattern_key,
	format_timestamp,
	hash_bytes,
	parse_timestamp,
	references_for_entries,
)

from codex_insights_facets_observations import event_summary


def pattern_id(kind: str, key: str) -> str:
	"""Return a stable identifier for one normalised pattern."""
	return f"{kind}-{hash_bytes(f'{kind}|{key}'.encode('utf-8'))[:12]}"


def pattern_key(observation: dict[str, object]) -> str:
	"""Return the grouping key for one observation.

	Corrections and approach changes keep one fixed key each until the extractor
	links them to the tool call being corrected; every other kind groups by its
	structured descriptor.
	"""
	kind = observation["kind"]
	if kind == "correction":
		return "user-authored-correction"
	if kind == "approach_change":
		return "user-authored-approach-change"
	return descriptor_pattern_key(observation.get("descriptor"))


def pattern_configuration_target(observation: dict[str, object]) -> bool:
	"""Return whether one observation names a configuration surface to inspect."""
	if observation["kind"] == "configuration_touch":
		return True

	target = observation.get("target")
	return isinstance(target, str) and bool(CONFIGURATION_TOKEN_PATTERN.search(target))


def configuration_tokens(target: str) -> list[str]:
	"""Return named configuration paths from one bounded tool target."""
	try:
		tokens = shlex.split(target)
	except ValueError:
		tokens = target.split()

	candidates = []
	for token in tokens:
		cleaned = token.strip("()[]{}<>,;:\"'")
		if CONFIGURATION_TOKEN_PATTERN.search(
			cleaned
		) or CONFIGURATION_BASENAME_PATTERN.match(cleaned):
			candidates.append(cleaned)

	return list(dict.fromkeys(candidates))


def configuration_markers_for_pattern(
	kind: str, observed_pattern: str
) -> tuple[str, ...]:
	"""Return the observed pattern detail used to check one configuration surface."""
	prefix = f"{kind}:"
	marker = observed_pattern.strip()
	if marker.casefold().startswith(prefix.casefold()):
		marker = marker[len(prefix) :].strip()

	return (marker,) if marker else ()


def configuration_status(
	target: object,
	project_path: object,
	required_markers: Iterable[str] = (),
) -> dict[str, object]:
	"""Read one named current configuration surface before recommending a change."""
	if not isinstance(target, str) or not target:
		return {"status": "ambiguous", "surface": None, "path": None, "read": False}
	tokens = configuration_tokens(target)
	if len(tokens) != 1:
		return {
			"status": "ambiguous",
			"surface": tokens or None,
			"path": None,
			"read": False,
		}

	surface = tokens[0]
	surface_path = Path(surface).expanduser()
	if not surface_path.is_absolute():
		base = Path(project_path).expanduser() if project_path else Path.cwd()
		surface_path = base / surface_path
	try:
		surface_path = surface_path.resolve()
	except OSError:
		return {
			"status": "unavailable",
			"surface": surface,
			"path": None,
			"read": False,
		}

	if not surface_path.exists():
		return {
			"status": "missing",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
		}
	if not surface_path.is_file():
		return {
			"status": "ambiguous",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
		}

	try:
		contents = surface_path.read_bytes()
	except OSError:
		return {
			"status": "unavailable",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
		}
	if len(contents) > MAX_CONFIGURATION_BYTES:
		return {
			"status": "unavailable",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
			"reason": "configuration_surface_exceeds_bound",
		}

	try:
		text = contents.decode("utf-8")
	except UnicodeDecodeError:
		return {
			"status": "unavailable",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
			"reason": "configuration_surface_is_not_utf8",
		}

	marker_values = [marker.casefold() for marker in required_markers]
	if marker_values and all(marker in text.casefold() for marker in marker_values):
		status = "already_remediated"
	else:
		status = "present_but_ignored"
	return {
		"status": status,
		"surface": surface,
		"path": surface_path.as_posix(),
		"read": True,
		"sha256": hash_bytes(contents),
		"byte_count": len(contents),
	}


def configuration_status_for_pattern(
	observations: list[dict[str, object]],
	cache: dict[tuple[str, str, tuple[str, ...]], dict[str, object]],
	kind: str,
	observed_pattern: str,
) -> list[dict[str, object]]:
	"""Inspect each project surface represented by a pattern's observations."""
	required_markers = configuration_markers_for_pattern(kind, observed_pattern)
	statuses = []
	for observation in observations:
		if not pattern_configuration_target(observation):
			continue
		target = observation.get("target")
		project_path = observation.get("project_path")
		cache_key = (str(project_path or ""), str(target or ""), required_markers)
		if cache_key not in cache:
			cache[cache_key] = configuration_status(
				target, project_path, required_markers
			)
		status = cache[cache_key]
		if status not in statuses:
			statuses.append(status)

	return statuses


def build_patterns(
	observations: list[dict[str, object]],
	configuration_cache: dict[tuple[str, str], dict[str, object]],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
	"""Group observations by kind and descriptor key across unique conversations."""
	groups: dict[tuple[str, str], list[dict[str, object]]] = {}
	for observation in observations[:MAX_PATTERN_OBSERVATIONS]:
		key = (observation["kind"], pattern_key(observation))
		groups.setdefault(key, []).append(observation)

	patterns = []
	for (kind, key), group in sorted(groups.items()):
		conversation_ids = sorted(
			{
				observation["conversation_id"]
				for observation in group
				if isinstance(observation.get("conversation_id"), str)
			}
		)
		citations = []
		for conversation_id in conversation_ids:
			conversation_group = [
				observation
				for observation in group
				if observation.get("conversation_id") == conversation_id
			]
			first = conversation_group[0]
			references = references_for_entries(conversation_group)
			citations.append(
				{
					"conversation_id": conversation_id,
					"rollout_id": first.get("rollout_id"),
					"timestamp": first.get("timestamp"),
					"evidence_references": references[
						:MAX_EVIDENCE_REFERENCES_PER_CITATION
					],
					"detail": event_summary(first),
				}
			)
		for observation in group:
			if (
				observation.get("conversation_id") is None
				and len(citations) < MAX_PATTERN_CITATIONS
			):
				citations.append(
					{
						"conversation_id": None,
						"rollout_id": observation.get("rollout_id"),
						"timestamp": observation.get("timestamp"),
						"evidence_references": observation["evidence_references"][
							:MAX_EVIDENCE_REFERENCES_PER_CITATION
						],
						"detail": event_summary(observation),
					}
				)

		first_timestamps = [
			parse_timestamp(observation.get("timestamp")) for observation in group
		]
		first_timestamps = [
			timestamp for timestamp in first_timestamps if timestamp is not None
		]
		labels = {
			observation.get("classification", {}).get("label")
			for observation in group
			if isinstance(observation.get("classification"), dict)
		}
		labels.discard(None)
		classification_label = (
			next(iter(labels)) if len(labels) == 1 else "mixed_causes"
		)
		observed_pattern = event_summary(group[0])
		configuration_statuses = configuration_status_for_pattern(
			group, configuration_cache, kind, observed_pattern
		)
		patterns.append(
			{
				"pattern_id": pattern_id(kind, key),
				"kind": kind,
				"key": key,
				"observed_pattern": observed_pattern,
				"occurrence_count": len(group),
				"unique_conversation_count": len(conversation_ids),
				"conversation_ids": conversation_ids,
				"recurrence_state": "repeated"
				if len(conversation_ids) >= 2
				else "illustrated_once"
				if conversation_ids
				else "unavailable",
				"time_span": {
					"since": format_timestamp(min(first_timestamps))
					if first_timestamps
					else None,
					"until": format_timestamp(max(first_timestamps))
					if first_timestamps
					else None,
					"state": "observed" if first_timestamps else "unavailable",
				},
				"classification": {
					"label": classification_label,
					"method": "deterministic_candidate_grouping",
					"confidence": "high" if len(conversation_ids) >= 2 else "low",
				},
				"supporting_evidence": citations[:MAX_PATTERN_CITATIONS],
				"evidence_references": references_for_entries(group),
				"configuration_statuses": configuration_statuses,
				"counterevidence_or_limitations": [
					"Only retained bounded evidence is available to this pass.",
					"A single conversation illustrates a pattern but does not establish recurrence."
					if len(conversation_ids) < 2
					else "Recurrence is counted across unique conversation IDs, not rollout rows.",
				],
			}
		)

	repeated_patterns = [
		pattern for pattern in patterns if pattern["recurrence_state"] == "repeated"
	]
	return patterns, repeated_patterns


def layer_for_surface(surface: object) -> str:
	"""Choose the owning configuration layer for one named surface."""
	value = str(surface or "").casefold()
	if "agents.md" in value:
		return "rule"
	if "workspace.md" in value:
		return "workflow"
	if "skill" in value:
		return "skill"
	if "hook" in value:
		return "hook"
	if "script" in value:
		return "script"
	return "tooling"


def run_selftest() -> None:
	"""Check that descriptor grouping merges same-file edits across checkouts and keeps unlike actions or files apart."""
	observations = [
		{
			"kind": "tool_failure",
			"target": "edit /tmp/run-a/project/src/check.py",
			"descriptor": {
				"action": "edit file",
				"tool": "apply_patch",
				"target": {
					"type": "file",
					"value": "/tmp/run-a/project/src/check.py",
				},
				"repo": "/tmp/run-a/project",
				"outcome": "fail",
			},
			"evidence_references": [],
			"conversation_id": "conversation-a",
			"rollout_id": "rollout-a",
			"timestamp": "2026-08-08T10:00:00Z",
			"classification": {},
		},
		{
			"kind": "tool_failure",
			"target": "edit /private/tmp/run-b/project/src/check.py",
			"descriptor": {
				"action": "edit file",
				"tool": "apply_patch",
				"target": {
					"type": "file",
					"value": "/private/tmp/run-b/project/src/check.py",
				},
				"repo": "/private/tmp/run-b/project",
				"outcome": "fail",
			},
			"evidence_references": [],
			"conversation_id": "conversation-b",
			"rollout_id": "rollout-b",
			"timestamp": "2026-08-08T10:01:00Z",
			"classification": {},
		},
		{
			"kind": "tool_failure",
			"target": "ruff check",
			"descriptor": {
				"action": "run lint",
				"tool": "exec",
				"target": {"type": "executable", "value": "ruff"},
				"repo": "/tmp/run-c/project",
				"outcome": "fail",
			},
			"evidence_references": [],
			"conversation_id": "conversation-c",
			"rollout_id": "rollout-c",
			"timestamp": "2026-08-08T10:02:00Z",
			"classification": {},
		},
		{
			"kind": "tool_failure",
			"target": "edit /tmp/run-d/project/src/other.py",
			"descriptor": {
				"action": "edit file",
				"tool": "apply_patch",
				"target": {"type": "file", "value": "/tmp/run-d/project/src/other.py"},
				"repo": "/tmp/run-d/project",
				"outcome": "fail",
			},
			"evidence_references": [],
			"conversation_id": "conversation-d",
			"rollout_id": "rollout-d",
			"timestamp": "2026-08-08T10:03:00Z",
			"classification": {},
		},
	]

	assert pattern_key(observations[0]) == "edit file|file|src/check.py|project"
	patterns, repeated_patterns = build_patterns(observations, {})
	assert len(patterns) == 3
	assert len(repeated_patterns) == 1
	assert repeated_patterns[0]["key"] == "edit file|file|src/check.py|project"
	assert repeated_patterns[0]["unique_conversation_count"] == 2
	assert {pattern["key"] for pattern in patterns} == {
		"edit file|file|src/check.py|project",
		"edit file|file|src/other.py|project",
		"run lint|executable|ruff|project",
	}


if __name__ == "__main__":
	run_selftest()

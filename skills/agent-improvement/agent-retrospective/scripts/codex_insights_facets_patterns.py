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
	"""Make a stable identifier for a grouped pattern.

	Args:
		kind: The observation kind in the group.
		key: The group's key from pattern_key: a fixed key for corrections and
			approach changes, otherwise the descriptor key.

	Returns:
		The kind followed by a shortened hash of the kind and key.
	"""
	return f"{kind}-{hash_bytes(f'{kind}|{key}'.encode('utf-8'))[:12]}"


def pattern_key(observation: dict[str, object]) -> str:
	"""Return the grouping key for one observation.

	Corrections and approach changes keep one fixed key each until the extractor
	links them to the tool call being corrected; every other kind groups by its
	structured descriptor.

	Args:
		observation: The observation to place in a pattern group.

	Returns:
		A fixed key for corrections or approach changes, otherwise the descriptor key.
	"""
	# The observation kind selects fixed or descriptor-based grouping.
	kind = observation["kind"]
	if kind == "correction":
		return "user-authored-correction"
	if kind == "approach_change":
		return "user-authored-approach-change"
	return descriptor_pattern_key(observation.get("descriptor"))


def pattern_configuration_target(observation: dict[str, object]) -> bool:
	"""Check whether an observation names a configuration surface.

	Args:
		observation: The observation with its kind and possible target text.

	Returns:
		Whether its kind or target text identifies a configuration surface.
	"""
	if observation["kind"] == "configuration_touch":
		return True

	# Target text may name a configuration file even for another observation kind.
	target = observation.get("target")
	return isinstance(target, str) and bool(CONFIGURATION_TOKEN_PATTERN.search(target))


def configuration_tokens(target: str) -> list[str]:
	"""Find configuration paths named in tool target text.

	Args:
		target: The tool target text to split into path candidates.

	Returns:
		Distinct matching paths in their first-seen order.
	"""
	try:
		# Shell-style splitting preserves quoted paths when the text is valid.
		tokens = shlex.split(target)
	except ValueError:
		# Plain splitting still yields candidates from malformed shell text.
		tokens = target.split()

	# The tokens that look like configuration paths, possibly repeated.
	candidates = []
	# Each token is checked after surrounding command punctuation is stripped.
	for token in tokens:
		# The cleaned token may match a path pattern or a known file name.
		cleaned = token.strip("()[]{}<>,;:\"'")
		if CONFIGURATION_TOKEN_PATTERN.search(
			cleaned
		) or CONFIGURATION_BASENAME_PATTERN.match(cleaned):
			candidates.append(cleaned)

	return list(dict.fromkeys(candidates))


def configuration_markers_for_pattern(
	kind: str, observed_pattern: str
) -> tuple[str, ...]:
	"""Get the pattern text used to check a configuration surface.

	Args:
		kind: The observation kind that may prefix the pattern text.
		observed_pattern: The displayed pattern text to trim.

	Returns:
		A one-item tuple with non-empty detail, or an empty tuple.
	"""
	# A kind prefix is removed before the detail is compared with file text.
	prefix = f"{kind}:"
	# Whitespace around the displayed pattern is ignored.
	marker = observed_pattern.strip()
	if marker.casefold().startswith(prefix.casefold()):
		marker = marker[len(prefix) :].strip()

	return (marker,) if marker else ()


def configuration_status(
	target: object,
	project_path: object,
	required_markers: Iterable[str] = (),
) -> dict[str, object]:
	"""Check one named configuration surface for observed pattern text.

	Args:
		target: Tool target text that should name exactly one configuration path;
			anything else is reported as ambiguous.
		project_path: The project folder used for relative paths; when it is empty,
			the current folder is used.
		required_markers: Text that must all appear in the file, ignoring case, for
			the guidance to count as already in place. With none, a readable file
			is reported as present_but_ignored.

	Returns:
		The status, the surface named in the target (or the list of paths found
		when there are several), the resolved path, and whether the file was read.
		A read file adds its hash and size; a file that is too large or not UTF-8
		adds a reason.
	"""
	if not isinstance(target, str) or not target:
		return {"status": "ambiguous", "surface": None, "path": None, "read": False}
	# Exactly one configuration path is needed for a current-status check.
	tokens = configuration_tokens(target)
	if len(tokens) != 1:
		return {
			"status": "ambiguous",
			"surface": tokens or None,
			"path": None,
			"read": False,
		}

	# The sole path token names the surface under inspection.
	surface = tokens[0]
	# A leading ~ in the path expands to the home folder.
	surface_path = Path(surface).expanduser()
	if not surface_path.is_absolute():
		# Relative paths use the named project folder or the current folder.
		base = Path(project_path).expanduser() if project_path else Path.cwd()
		surface_path = base / surface_path
	try:
		# The absolute path, with links followed, is the one reported in the status.
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
		# The raw file bytes are size-checked before they are decoded.
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
		# The file text that is searched for the marker text.
		text = contents.decode("utf-8")
	except UnicodeDecodeError:
		return {
			"status": "unavailable",
			"surface": surface,
			"path": surface_path.as_posix(),
			"read": False,
			"reason": "configuration_surface_is_not_utf8",
		}

	# Each required marker is normalised for a case-insensitive text check.
	marker_values = [marker.casefold() for marker in required_markers]
	if marker_values and all(marker in text.casefold() for marker in marker_values):
		# Every required marker appears in the file text.
		status = "already_remediated"
	else:
		# At least one marker is absent, or no markers were supplied.
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
	"""Inspect configuration surfaces named by a pattern's observations.

	Args:
		observations: The pattern's observations. Only those of kind
			configuration_touch, or whose target text names a configuration file,
			are checked.
		cache: Surface checks keyed by project, target, and marker text. New
			results are added to it, so later patterns reuse them.
		kind: The pattern kind used to trim its displayed text.
		observed_pattern: The displayed text checked against each surface.

	Returns:
		Distinct surface statuses in observation order.
	"""
	# Pattern detail provides the text checked against each named surface.
	required_markers = configuration_markers_for_pattern(kind, observed_pattern)
	# The distinct surface statuses found so far, in observation order.
	statuses = []
	# Each observation may name a surface worth checking.
	for observation in observations:
		if not pattern_configuration_target(observation):
			continue
		# Target and project path identify the surface named by this observation.
		target = observation.get("target")
		project_path = observation.get("project_path")
		# The cache also distinguishes different required marker text.
		cache_key = (str(project_path or ""), str(target or ""), required_markers)
		if cache_key not in cache:
			cache[cache_key] = configuration_status(
				target, project_path, required_markers
			)
		# The cached status is added only if this result is not already present.
		status = cache[cache_key]
		if status not in statuses:
			statuses.append(status)

	return statuses


def build_patterns(
	observations: list[dict[str, object]],
	configuration_cache: dict[tuple[str, str, tuple[str, ...]], dict[str, object]],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
	"""Group observations into patterns and pick out the repeated ones.

	Args:
		observations: The candidate observations; only the first
			MAX_PATTERN_OBSERVATIONS are grouped.
		configuration_cache: Results of configuration surface checks. New results
			are added to it, so a caller can share it across calls.

	Returns:
		All grouped patterns and the subset repeated across conversations.
	"""
	# The observations in each group, keyed by kind and grouping key.
	groups: dict[tuple[str, str], list[dict[str, object]]] = {}
	# Each retained observation contributes to one pattern group.
	for observation in observations[:MAX_PATTERN_OBSERVATIONS]:
		# The grouping key pairs the observation kind with its pattern_key.
		key = (observation["kind"], pattern_key(observation))
		groups.setdefault(key, []).append(observation)

	# Pattern documents are built in sorted group-key order.
	patterns = []
	# Each group becomes one pattern with citations and recurrence state.
	for (kind, key), group in sorted(groups.items()):
		# The distinct conversation IDs in the group; IDs that are not strings are
		# left out, so they never count towards recurrence.
		conversation_ids = sorted(
			{
				observation["conversation_id"]
				for observation in group
				if isinstance(observation.get("conversation_id"), str)
			}
		)
		# Citations start with one representative per available conversation ID.
		citations = []
		# Each distinct conversation contributes a citation from its first observation.
		for conversation_id in conversation_ids:
			# Observations from this conversation supply its citation references.
			conversation_group = [
				observation
				for observation in group
				if observation.get("conversation_id") == conversation_id
			]
			# The first observation supplies the citation's rollout and timestamp.
			first = conversation_group[0]
			# All observations in this conversation contribute references.
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
		# Observations without a conversation ID may fill remaining citation slots.
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

		# Parsed timestamps establish the first and last observed times.
		first_timestamps = [
			parse_timestamp(observation.get("timestamp")) for observation in group
		]
		# Missing or invalid timestamps are excluded from the time span.
		first_timestamps = [
			timestamp for timestamp in first_timestamps if timestamp is not None
		]
		# The distinct classification labels across the group's observations.
		labels = {
			observation.get("classification", {}).get("label")
			for observation in group
			if isinstance(observation.get("classification"), dict)
		}
		labels.discard(None)
		# One shared label names the cause; no label or several labels give
		# mixed_causes.
		classification_label = (
			next(iter(labels)) if len(labels) == 1 else "mixed_causes"
		)
		# The first observation supplies the displayed pattern description.
		observed_pattern = event_summary(group[0])
		# Configuration surfaces named by the group's observations are checked
		# against that description.
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

	# Only groups with at least two conversation IDs are repeated patterns.
	repeated_patterns = [
		pattern for pattern in patterns if pattern["recurrence_state"] == "repeated"
	]
	return patterns, repeated_patterns


def layer_for_surface(surface: object) -> str:
	"""Choose a configuration layer from a surface name.

	Args:
		surface: The path or surface name to classify.

	Returns:
		The rule, workflow, skill, hook, script, or tooling layer.
	"""
	# Case-insensitive path text supplies the layer hints.
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
	"""Check that grouping merges matching edits across checkouts.

	The checks also confirm that edits to other files and lint actions stay in
	separate groups, and check the repeated group's conversation count and key.
	"""
	# The sample observations cover matching edits, another file, and a lint action.
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
	# The sample should produce three groups, with only the matching edits repeated.
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

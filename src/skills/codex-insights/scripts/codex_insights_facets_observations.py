#!/usr/bin/env python3
"""Derive bounded conversation observations from Codex evidence."""

from __future__ import annotations

from typing import Iterable

from codex_insights_facets_common import (
	CANDIDATE_FIELDS,
	MAX_EVENTS_PER_CONVERSATION,
	MAX_EVIDENCE_REFERENCES_PER_CITATION,
	MAX_LIMITATIONS_PER_CONVERSATION,
	MAX_TURNS_PER_ROLLOUT,
	available_conversation_id,
	bounded_text,
	descriptor_for_entries,
	earliest_timestamp,
	event_classification,
	format_timestamp,
	parse_timestamp,
	references_for_entries,
	require_mapping,
)


def derive_turns(
	rollout: dict[str, object], evidence_index: dict[str, dict[str, object]]
) -> list[dict[str, object]]:
	"""Derive bounded authored-user turns from ordered retained evidence."""
	evidence = rollout.get("evidence", [])
	if not isinstance(evidence, list):
		return []

	authored_indexes = [
		index
		for index, entry in enumerate(evidence)
		if entry.get("kind") == "authored_user_message"
	]
	turns = []
	for turn_index, start_index in enumerate(
		authored_indexes[:MAX_TURNS_PER_ROLLOUT], start=1
	):
		end_index = (
			authored_indexes[turn_index]
			if turn_index < len(authored_indexes)
			else len(evidence)
		)
		entries = evidence[start_index:end_index]
		references = [
			entry["reference"]
			for entry in entries
			if entry.get("reference") in evidence_index
		]
		if not references:
			continue

		turns.append(
			{
				"turn_index": turn_index,
				"evidence_references": references[
					: MAX_EVIDENCE_REFERENCES_PER_CITATION * 4
				],
				"start_timestamp": format_timestamp(
					evidence_index[references[0]].get("timestamp")
				),
				"classification": {
					"label": "authored_turn",
					"method": "ordered_retained_evidence",
					"confidence": "high",
				},
			}
		)

	return turns


def candidate_event(
	rollout: dict[str, object],
	candidate_value: dict[str, object],
	kind: str,
	evidence_index: dict[str, dict[str, object]],
) -> dict[str, object]:
	"""Convert one extractor candidate into a traceable facet observation."""
	references = list(candidate_value["evidence_references"])
	status = candidate_value.get("status")
	target = bounded_text(candidate_value.get("target"), 280)
	structure_entries = []
	for ledger_value in rollout.get("tool_ledger", []):
		ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
		ledger_references = {
			reference
			for reference in (
				ledger_entry.get("call_reference"),
				ledger_entry.get("result_reference"),
			)
			if isinstance(reference, str)
		}
		if ledger_references.intersection(references):
			structure_entries.append(ledger_entry)
	if not structure_entries:
		# Raw evidence_index entries never carry a "status" key, so the failed-command
		# executable target rule cannot fire through this fallback; it degrades to a
		# null target rather than guessing one.
		structure_entries = [
			evidence_index[reference]
			for reference in references
			if reference in evidence_index
		]
	return {
		"kind": kind,
		"source": bounded_text(candidate_value.get("source"), 80),
		"target": target,
		"status": status,
		"descriptor": descriptor_for_entries(
			kind, structure_entries, rollout.get("project_path"), status
		),
		"evidence_references": references,
		"timestamp": earliest_timestamp([candidate_value], evidence_index),
		"conversation_id": available_conversation_id(rollout),
		"rollout_id": rollout.get("rollout_id"),
		"classification": event_classification(kind, status),
	}


def ledger_event(
	rollout: dict[str, object],
	ledger_entry: dict[str, object],
	kind: str,
	evidence_index: dict[str, dict[str, object]],
) -> dict[str, object]:
	"""Convert one bounded tool ledger entry into a facet observation."""
	references = [
		reference
		for reference in (
			ledger_entry.get("call_reference"),
			ledger_entry.get("result_reference"),
		)
		if isinstance(reference, str)
	]
	return {
		"kind": kind,
		"source": ledger_entry.get("status_source"),
		"target": bounded_text(ledger_entry.get("target"), 280),
		"status": ledger_entry.get("status"),
		"descriptor": descriptor_for_entries(
			kind,
			[ledger_entry],
			rollout.get("project_path"),
			ledger_entry.get("status"),
		),
		"expected_probe": ledger_entry.get("expected_probe"),
		"evidence_references": references,
		"timestamp": earliest_timestamp(
			[{"evidence_references": references}], evidence_index
		),
		"conversation_id": available_conversation_id(rollout),
		"rollout_id": rollout.get("rollout_id"),
		"classification": event_classification(kind, ledger_entry.get("status")),
	}


def recovery_event(
	friction_event: dict[str, object],
	rollout: dict[str, object],
	ledger_entry: dict[str, object],
	evidence_index: dict[str, dict[str, object]],
) -> dict[str, object]:
	"""Build one recovery observation from friction followed by a passing tool action."""
	resolution_references = [
		reference
		for reference in (
			ledger_entry.get("call_reference"),
			ledger_entry.get("result_reference"),
		)
		if isinstance(reference, str)
	]
	evidence_references = references_for_entries(
		[
			friction_event,
			{"evidence_references": resolution_references},
		]
	)
	target = bounded_text(ledger_entry.get("target"), 280) or friction_event.get(
		"target"
	)
	return {
		"kind": "recovery",
		"source": friction_event["kind"],
		"target": target,
		"status": ledger_entry.get("status"),
		"descriptor": {
			**descriptor_for_entries(
				"recovery",
				[ledger_entry],
				rollout.get("project_path"),
				ledger_entry.get("status"),
			),
			"source": friction_event["kind"],
		},
		"expected_probe": ledger_entry.get("expected_probe"),
		"evidence_references": evidence_references,
		"timestamp": earliest_timestamp(
			[
				friction_event,
				{"evidence_references": resolution_references},
			],
			evidence_index,
		),
		"conversation_id": available_conversation_id(rollout),
		"rollout_id": friction_event.get("rollout_id"),
		"classification": event_classification("recovery", ledger_entry.get("status")),
	}


def recovery_observations(
	rollouts: list[dict[str, object]],
	observations: list[dict[str, object]],
	evidence_index: dict[str, dict[str, object]],
) -> list[dict[str, object]]:
	"""Build recovery observations when friction precedes a passing tool action.

	A friction event pairs with the first later successful ledger entry that has the
	same target text and tool. Each success resolves at most one friction event, so
	a single passing run cannot count as recovery for several earlier failures.
	Friction events without a target never pair.
	"""
	resolving_actions = []
	for rollout in rollouts:
		for ledger_value in rollout.get("tool_ledger", []):
			ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
			if ledger_entry.get("status") != "success":
				continue

			references = [
				reference
				for reference in (
					ledger_entry.get("call_reference"),
					ledger_entry.get("result_reference"),
				)
				if isinstance(reference, str)
			]
			timestamp = earliest_timestamp(
				[{"evidence_references": references}], evidence_index
			)
			parsed_timestamp = parse_timestamp(timestamp)
			if parsed_timestamp is not None:
				resolving_actions.append((parsed_timestamp, rollout, ledger_entry))

	resolving_actions.sort(key=lambda value: value[0])

	friction_events = []
	for index, event in enumerate(observations):
		if event["kind"] not in {
			"tool_failure",
			"correction",
			"rollback",
			"interruption",
		}:
			continue

		friction_timestamp = parse_timestamp(event.get("timestamp"))
		if friction_timestamp is not None:
			friction_events.append((friction_timestamp, index, event))
	friction_events.sort(key=lambda value: (value[0], value[1]))
	recoveries = []
	used_resolutions = set()
	for friction_timestamp, _, friction_event in friction_events:
		friction_target = bounded_text(friction_event.get("target"), 280)
		if friction_target is None:
			continue

		friction_descriptor = friction_event.get("descriptor")
		friction_tool = (
			friction_descriptor.get("tool")
			if isinstance(friction_descriptor, dict)
			else None
		)
		resolving_action = next(
			(
				(index, resolution)
				for index, resolution in enumerate(resolving_actions)
				if (
					index not in used_resolutions
					and resolution[0] > friction_timestamp
					and friction_target
					== bounded_text(resolution[2].get("target"), 280)
					and friction_tool == resolution[2].get("tool")
				)
			),
			None,
		)
		if resolving_action is None:
			continue

		resolution_index, resolution = resolving_action
		used_resolutions.add(resolution_index)
		_, rollout, ledger_entry = resolution
		recoveries.append(
			recovery_event(friction_event, rollout, ledger_entry, evidence_index)
		)

	return recoveries


def derive_observations(
	rollout: dict[str, object], evidence_index: dict[str, dict[str, object]]
) -> list[dict[str, object]]:
	"""Derive all bounded behavioural observations from one extractor rollout."""
	observations = []
	seen = set()

	def add_observation(observation: dict[str, object]) -> None:
		"""Keep one observation per kind and evidence set within the conversation bound."""
		references = tuple(observation["evidence_references"])
		identity = (observation["kind"], references)
		if (
			not references
			or identity in seen
			or len(observations) >= MAX_EVENTS_PER_CONVERSATION
		):
			return

		seen.add(identity)
		observations.append(observation)

	for field_name, kind in CANDIDATE_FIELDS.items():
		for candidate_value in rollout.get("candidates", {}).get(field_name, []):
			add_observation(
				candidate_event(rollout, candidate_value, kind, evidence_index)
			)

	for ledger_value in rollout.get("tool_ledger", []):
		ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
		status = ledger_entry.get("status")
		expected_probe = ledger_entry.get("expected_probe")
		if status == "failure" and expected_probe != "explicit":
			add_observation(
				ledger_event(rollout, ledger_entry, "tool_failure", evidence_index)
			)
		if status == "unknown" and expected_probe != "explicit":
			add_observation(
				ledger_event(rollout, ledger_entry, "verification_gap", evidence_index)
			)

	return observations


def event_summary(event: dict[str, object]) -> str:
	"""Describe one observation without exposing more transcript content than needed."""
	kind = event["kind"]
	if kind == "recovery":
		source = event.get("source")
		if isinstance(source, str) and source:
			kind = f"{kind} from {source}"
	target = event.get("target")
	if isinstance(target, str) and target:
		return f"{kind}: {target}"

	return str(kind)


def limitation(
	kind: str, summary: str, references: Iterable[str] = ()
) -> dict[str, object]:
	"""Build one explicit limitation or unavailable state."""
	return {
		"kind": kind,
		"summary": summary,
		"evidence_references": list(references),
		"confidence": "high" if kind == "unavailable" else "medium",
	}


def conversation_facet(
	conversation_id: str | None,
	rollouts: list[dict[str, object]],
	evidence_index: dict[str, dict[str, object]],
) -> tuple[dict[str, object], list[dict[str, object]]]:
	"""Build one bounded per-conversation facet and its pattern observations.

	Recoveries take up to half of MAX_EVENTS_PER_CONVERSATION and the other
	observations fill whatever remains, so a conversation with no recoveries keeps
	the full cap for them.
	"""
	all_evidence = []
	base_observations = []
	for rollout in rollouts:
		all_evidence.extend(
			entry for entry in rollout.get("evidence", []) if isinstance(entry, dict)
		)
		base_observations.extend(derive_observations(rollout, evidence_index))
	max_recoveries = MAX_EVENTS_PER_CONVERSATION // 2
	recoveries = recovery_observations(rollouts, base_observations, evidence_index)
	kept_recoveries = recoveries[:max_recoveries]
	base_observations = base_observations[
		: MAX_EVENTS_PER_CONVERSATION - len(kept_recoveries)
	]
	all_observations = base_observations + kept_recoveries
	authored_messages = [
		entry for entry in all_evidence if entry.get("kind") == "authored_user_message"
	]
	goal_entry = authored_messages[0] if authored_messages else None
	goal = (
		{
			"state": "observed",
			"text": bounded_text(goal_entry.get("excerpt")),
			"evidence_references": [goal_entry["reference"]],
			"classification": "task_goal",
			"confidence": "medium",
		}
		if goal_entry is not None
		else {
			"state": "unavailable",
			"text": None,
			"evidence_references": [],
			"classification": "task_goal",
			"confidence": "high",
		}
	)

	lifecycle_entries = [
		entry
		for entry in all_evidence
		if entry.get("kind") in {"lifecycle_event", "rollback_event"}
	]
	lifecycle_types = {entry.get("event_type") for entry in lifecycle_entries}
	if "task_complete" in lifecycle_types:
		outcome_state = "completed"
	elif "thread_rolled_back" in lifecycle_types:
		outcome_state = "rolled_back"
	elif "turn_aborted" in lifecycle_types:
		outcome_state = "interrupted"
	elif any(rollout.get("activity_state") == "live" for rollout in rollouts):
		outcome_state = "live"
	else:
		outcome_state = "unknown"
	outcome_references = [entry["reference"] for entry in lifecycle_entries]
	outcome = {
		"state": outcome_state,
		"evidence_references": outcome_references,
		"classification": outcome_state,
		"confidence": "high" if lifecycle_entries else "low",
	}

	friction_kinds = {
		"tool_failure",
		"correction",
		"retry",
		"verification_gap",
		"interruption",
		"rollback",
	}
	friction_events = [
		{
			"kind": event["kind"],
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] in friction_kinds
	]
	user_interventions = [
		{
			"kind": event["kind"],
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] in {"correction", "approach_change"}
	]
	verification_gaps = [
		{
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] == "verification_gap"
	]
	approach_changes = [
		{
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] == "approach_change"
	]

	limitations = [
		limitation(
			"classifier",
			"Semantic labels are deterministic candidate classifications, not model judgements.",
		)
	]
	for rollout in rollouts:
		for unavailable in rollout.get("unavailable", []):
			limitations.append(
				limitation(
					"unavailable",
					str(unavailable),
					rollout.get("uncertain_user_message_references", []),
				)
			)
		truncation = rollout.get("truncation", {})
		if isinstance(truncation, dict) and any(value for value in truncation.values()):
			limitations.append(
				limitation(
					"truncated",
					"The extractor bound omitted some records or candidates.",
					[],
				)
			)
	if len(limitations) > MAX_LIMITATIONS_PER_CONVERSATION:
		limitations = limitations[:MAX_LIMITATIONS_PER_CONVERSATION]

	turns = []
	for rollout in rollouts:
		turns.extend(derive_turns(rollout, evidence_index))
	all_references = references_for_entries(
		[
			{"evidence_references": [entry["reference"] for entry in all_evidence]},
			*all_observations,
		]
	)
	start_timestamps = [
		parse_timestamp(rollout.get("start_timestamp")) for rollout in rollouts
	]
	end_timestamps = [
		parse_timestamp(rollout.get("end_timestamp")) for rollout in rollouts
	]
	start_timestamps = [
		timestamp for timestamp in start_timestamps if timestamp is not None
	]
	end_timestamps = [
		timestamp for timestamp in end_timestamps if timestamp is not None
	]
	facet = {
		"conversation_id": conversation_id,
		"conversation_id_state": "available"
		if conversation_id is not None
		else "unavailable",
		"rollout_ids": [rollout.get("rollout_id") for rollout in rollouts],
		"time_span": {
			"since": format_timestamp(min(start_timestamps))
			if start_timestamps
			else None,
			"until": format_timestamp(max(end_timestamps)) if end_timestamps else None,
			"state": "observed" if start_timestamps else "unavailable",
		},
		"task_goal": goal,
		"outcome": outcome,
		"turns": turns[:MAX_TURNS_PER_ROLLOUT],
		"friction_events": friction_events,
		"user_interventions": user_interventions,
		"verification_gaps": verification_gaps,
		"approach_changes": approach_changes,
		"current_limitations": limitations,
		"evidence_references": all_references,
		"confidence": "medium" if conversation_id is not None else "low",
	}
	return facet, all_observations


def run_selftest() -> None:
	"""Verify descriptor construction resolves a structural target and leaves one null otherwise."""
	evidence_index = {
		"tool": {"reference": "tool", "timestamp": "2026-08-08T10:00:00Z"},
		"user": {"reference": "user", "timestamp": "2026-08-08T10:00:01Z"},
	}
	rollout = {
		"rollout_id": "rollout",
		"conversation_id": "conversation",
		"project_path": "/tmp/project",
		"tool_ledger": [
			{
				"call_reference": "tool",
				"result_reference": None,
				"status": "failure",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			}
		],
	}
	resolved = ledger_event(
		rollout, rollout["tool_ledger"][0], "tool_failure", evidence_index
	)
	assert resolved["descriptor"] == {
		"action": "run lint",
		"tool": "exec",
		"target": {"type": "executable", "value": "ruff"},
		"repo": "/tmp/project",
		"outcome": "fail",
	}
	unknown = candidate_event(
		rollout,
		{"evidence_references": ["user"]},
		"correction",
		evidence_index,
	)
	assert unknown["descriptor"] == {
		"action": "record event",
		"tool": None,
		"target": {"type": None, "value": None},
		"repo": "/tmp/project",
		"outcome": "unknown",
	}

	recovery_evidence_index = {
		reference: {
			"reference": reference,
			"timestamp": timestamp,
		}
		for reference, timestamp in (
			("early-success-call", "2026-08-08T10:00:00Z"),
			("early-success-result", "2026-08-08T10:00:01Z"),
			("failure-call", "2026-08-08T10:01:00Z"),
			("failure-result", "2026-08-08T10:01:01Z"),
			("success-call-1", "2026-08-08T10:02:00Z"),
			("success-result-1", "2026-08-08T10:02:01Z"),
			("success-call-2", "2026-08-08T10:03:00Z"),
			("success-result-2", "2026-08-08T10:03:01Z"),
			("success-call-3", "2026-08-08T10:04:00Z"),
			("success-result-3", "2026-08-08T10:04:01Z"),
			("success-call-4", "2026-08-08T10:05:00Z"),
			("success-result-4", "2026-08-08T10:05:01Z"),
			("unrelated-success-call", "2026-08-08T10:06:00Z"),
			("unrelated-success-result", "2026-08-08T10:06:01Z"),
		)
	}
	recovery_rollout = {
		"rollout_id": "recovery-rollout",
		"conversation_id": "recovery-conversation",
		"project_path": "/tmp/project",
		"tool_ledger": [
			{
				"call_reference": "early-success-call",
				"result_reference": "early-success-result",
				"status": "success",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "failure-call",
				"result_reference": "failure-result",
				"status": "failure",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "success-call-1",
				"result_reference": "success-result-1",
				"status": "success",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "success-call-2",
				"result_reference": "success-result-2",
				"status": "success",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "success-call-3",
				"result_reference": "success-result-3",
				"status": "success",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "success-call-4",
				"result_reference": "success-result-4",
				"status": "success",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "unrelated-success-call",
				"result_reference": "unrelated-success-result",
				"status": "success",
				"target": "pytest tests",
				"tool": "exec",
				"command_argv": ["pytest", "tests"],
			},
		],
		"candidates": {
			"corrections": [
				{"evidence_references": ["failure-call"], "target": "ruff check"}
			],
			"rollbacks": [
				{"evidence_references": ["failure-call"], "target": "ruff check"}
			],
			"interruptions": [
				{"evidence_references": ["failure-call"], "target": "ruff check"}
			],
		},
		"evidence": [],
	}
	_, recovery_observation_values = conversation_facet(
		"recovery-conversation", [recovery_rollout], recovery_evidence_index
	)
	recovery_values = [
		event for event in recovery_observation_values if event["kind"] == "recovery"
	]
	assert len(recovery_values) == 4
	assert {event["source"] for event in recovery_values} == {
		"tool_failure",
		"correction",
		"rollback",
		"interruption",
	}
	assert {
		event["source"]: event["evidence_references"][-2:] for event in recovery_values
	} == {
		"correction": ["success-call-1", "success-result-1"],
		"interruption": ["success-call-2", "success-result-2"],
		"rollback": ["success-call-3", "success-result-3"],
		"tool_failure": ["success-call-4", "success-result-4"],
	}
	assert all(event["target"] == "ruff check" for event in recovery_values)
	assert all(
		event["kind"]
		in {"tool_failure", "correction", "rollback", "interruption", "recovery"}
		for event in recovery_observation_values
	)

	negative_recovery_evidence_index = {
		reference: {
			"reference": reference,
			"timestamp": timestamp,
		}
		for reference, timestamp in (
			("null-target-friction", "2026-08-08T10:07:00Z"),
			("null-target-success-call", "2026-08-08T10:08:00Z"),
			("null-target-success-result", "2026-08-08T10:08:01Z"),
			("different-tool-friction-call", "2026-08-08T10:09:00Z"),
			("different-tool-friction-result", "2026-08-08T10:09:01Z"),
			("different-tool-success-call", "2026-08-08T10:10:00Z"),
			("different-tool-success-result", "2026-08-08T10:10:01Z"),
		)
	}
	negative_recovery_rollout = {
		"rollout_id": "negative-recovery-rollout",
		"conversation_id": "negative-recovery-conversation",
		"project_path": "/tmp/project",
		"tool_ledger": [
			{
				"call_reference": "null-target-success-call",
				"result_reference": "null-target-success-result",
				"status": "success",
				"target": None,
				"tool": None,
			},
			{
				"call_reference": "different-tool-friction-call",
				"result_reference": "different-tool-friction-result",
				"status": "failure",
				"target": "ruff check",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "different-tool-success-call",
				"result_reference": "different-tool-success-result",
				"status": "success",
				"target": "ruff check",
				"tool": "other",
			},
		],
		"candidates": {
			"corrections": [
				{"evidence_references": ["null-target-friction"]},
				{
					"evidence_references": ["different-tool-friction-call"],
					"target": "ruff check",
				},
			]
		},
		"evidence": [],
	}
	_, negative_recovery_observations = conversation_facet(
		"negative-recovery-conversation",
		[negative_recovery_rollout],
		negative_recovery_evidence_index,
	)
	assert not any(
		event["kind"] == "recovery" for event in negative_recovery_observations
	)

	from codex_insights_facets_patterns import build_patterns

	patterns, repeated_patterns = build_patterns(recovery_observation_values, {})
	recovery_patterns = [
		pattern for pattern in patterns if pattern["kind"] == "recovery"
	]
	assert len(recovery_patterns) == 4
	assert {pattern["observed_pattern"] for pattern in recovery_patterns} == {
		"recovery from correction: ruff check",
		"recovery from interruption: ruff check",
		"recovery from rollback: ruff check",
		"recovery from tool_failure: ruff check",
	}
	assert not any(pattern["kind"] == "recovery" for pattern in repeated_patterns)

	base_evidence_index = {
		f"base-{index}": {
			"reference": f"base-{index}",
			"timestamp": f"2026-08-08T11:{index // 60:02d}:{index % 60:02d}Z",
		}
		for index in range(MAX_EVENTS_PER_CONVERSATION)
	}
	base_only_rollout = {
		"rollout_id": "base-only-rollout",
		"conversation_id": "base-only-conversation",
		"project_path": "/tmp/project",
		"tool_ledger": [],
		"candidates": {
			"corrections": [
				{
					"evidence_references": [f"base-{index}"],
					"target": f"target-{index}",
				}
				for index in range(MAX_EVENTS_PER_CONVERSATION)
			]
		},
		"evidence": [],
	}
	_, base_only_observations = conversation_facet(
		"base-only-conversation", [base_only_rollout], base_evidence_index
	)
	assert len(base_only_observations) == MAX_EVENTS_PER_CONVERSATION

	success_only_rollout = {
		**recovery_rollout,
		"tool_ledger": [recovery_rollout["tool_ledger"][2]],
		"candidates": {},
	}
	_, success_only_observations = conversation_facet(
		"success-only-conversation", [success_only_rollout], recovery_evidence_index
	)
	assert not any(event["kind"] == "recovery" for event in success_only_observations)


if __name__ == "__main__":
	run_selftest()

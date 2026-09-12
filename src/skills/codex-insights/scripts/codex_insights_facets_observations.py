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
		"descriptor": descriptor_for_entries(
			"recovery",
			[ledger_entry],
			rollout.get("project_path"),
			ledger_entry.get("status"),
		),
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
	"""Build recovery observations when friction precedes a passing tool action."""
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
	recoveries = []
	for friction_event in observations:
		if friction_event["kind"] not in {
			"tool_failure",
			"correction",
			"rollback",
			"interruption",
		}:
			continue

		friction_timestamp = parse_timestamp(friction_event.get("timestamp"))
		if friction_timestamp is None:
			continue
		resolving_action = next(
			(
				resolution
				for resolution in resolving_actions
				if resolution[0] > friction_timestamp
			),
			None,
		)
		if resolving_action is None:
			continue

		_, rollout, ledger_entry = resolving_action
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
	"""Build one bounded per-conversation facet and its pattern observations."""
	all_evidence = []
	all_observations = []
	for rollout in rollouts:
		all_evidence.extend(
			entry for entry in rollout.get("evidence", []) if isinstance(entry, dict)
		)
		all_observations.extend(derive_observations(rollout, evidence_index))
	available_observations = MAX_EVENTS_PER_CONVERSATION - len(all_observations)
	if available_observations > 0:
		all_observations.extend(
			recovery_observations(rollouts, all_observations, evidence_index)[
				:available_observations
			]
		)
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
			("failure-call", "2026-08-08T10:01:00Z"),
			("failure-result", "2026-08-08T10:01:01Z"),
			("correction", "2026-08-08T10:02:00Z"),
			("rollback", "2026-08-08T10:03:00Z"),
			("interruption", "2026-08-08T10:04:00Z"),
			("success-call", "2026-08-08T10:05:00Z"),
			("success-result", "2026-08-08T10:05:01Z"),
		)
	}
	recovery_rollout = {
		"rollout_id": "recovery-rollout",
		"conversation_id": "recovery-conversation",
		"project_path": "/tmp/project",
		"tool_ledger": [
			{
				"call_reference": "failure-call",
				"result_reference": "failure-result",
				"status": "failure",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
			{
				"call_reference": "success-call",
				"result_reference": "success-result",
				"status": "success",
				"tool": "exec",
				"command_argv": ["ruff", "check"],
			},
		],
		"candidates": {
			"corrections": [{"evidence_references": ["correction"]}],
			"rollbacks": [{"evidence_references": ["rollback"]}],
			"interruptions": [{"evidence_references": ["interruption"]}],
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
	assert all(
		event["evidence_references"][-2:] == ["success-call", "success-result"]
		for event in recovery_values
	)
	assert all(
		event["kind"]
		in {"tool_failure", "correction", "rollback", "interruption", "recovery"}
		for event in recovery_observation_values
	)

	from codex_insights_facets_patterns import build_patterns

	patterns, repeated_patterns = build_patterns(recovery_observation_values, {})
	recovery_patterns = [
		pattern for pattern in patterns if pattern["kind"] == "recovery"
	]
	assert len(recovery_patterns) == 1
	assert not any(pattern["kind"] == "recovery" for pattern in repeated_patterns)

	success_only_rollout = {
		**recovery_rollout,
		"tool_ledger": [recovery_rollout["tool_ledger"][1]],
		"candidates": {},
	}
	_, success_only_observations = conversation_facet(
		"success-only-conversation", [success_only_rollout], recovery_evidence_index
	)
	assert not any(event["kind"] == "recovery" for event in success_only_observations)


if __name__ == "__main__":
	run_selftest()

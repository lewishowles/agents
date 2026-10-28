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
	"""Group retained evidence into authored-user turns, up to the rollout limit.

	Args:
		rollout: The extracted rollout with its ordered evidence.
		evidence_index: Evidence entries keyed by reference for their timestamps.

	Returns:
		Turns with bounded evidence references and their first timestamps.
	"""
	# The retained entries are the only evidence available for turn boundaries.
	evidence = rollout.get("evidence", [])
	if not isinstance(evidence, list):
		return []

	# The position of each user message, where a new turn begins.
	authored_indexes = [
		index
		for index, entry in enumerate(evidence)
		if entry.get("kind") == "authored_user_message"
	]
	# The turns that have at least one indexed evidence reference.
	turns = []
	# Each turn, numbered from 1, starts at a user message, up to the turn limit.
	for turn_index, start_index in enumerate(
		authored_indexes[:MAX_TURNS_PER_ROLLOUT], start=1
	):
		# The next user message ends this turn, or the evidence ends the last turn.
		end_index = (
			authored_indexes[turn_index]
			if turn_index < len(authored_indexes)
			else len(evidence)
		)
		# The retained entries belonging to this authored turn.
		entries = evidence[start_index:end_index]
		# The turn's evidence references that appear in the evidence index.
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
	"""Convert an extractor candidate into an observation tied to its evidence.

	Args:
		rollout: The rollout containing the candidate and tool ledger.
		candidate_value: The candidate's fields and evidence references.
		kind: The observation kind assigned to this candidate field.
		evidence_index: Evidence entries keyed by reference.

	Returns:
		The observation with its descriptor, classification and references.
	"""
	# The candidate's links to evidence, retained in their original order.
	references = list(candidate_value["evidence_references"])
	# The candidate's reported tool status, when present.
	status = candidate_value.get("status")
	# The bounded target text used to describe this candidate.
	target = bounded_text(candidate_value.get("target"), 280)
	# Ledger records that can supply a structural descriptor for this candidate.
	structure_entries = []
	# Each ledger entry that shares evidence with the candidate can describe its structure.
	for ledger_value in rollout.get("tool_ledger", []):
		# The validated mapping for this ledger record.
		ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
		# The ledger entry's call and result references that are present.
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
	"""Convert a tool ledger entry into an observation tied to its evidence.

	Args:
		rollout: The rollout that contains the ledger entry.
		ledger_entry: The tool action, result and status to describe.
		kind: The observation kind assigned to the ledger entry.
		evidence_index: Evidence entries keyed by reference.

	Returns:
		The observation with its descriptor, classification and references.
	"""
	# The tool call and result references that are present.
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
	"""Describe friction resolved by a later passing tool action.

	Args:
		friction_event: The earlier failure or intervention observation.
		rollout: The rollout containing the passing tool action.
		ledger_entry: The passing tool action that resolves the friction.
		evidence_index: Evidence entries keyed by reference.

	Returns:
		A recovery observation linked to the friction and passing action.
	"""
	# The passing action's call and result references that are present.
	resolution_references = [
		reference
		for reference in (
			ledger_entry.get("call_reference"),
			ledger_entry.get("result_reference"),
		)
		if isinstance(reference, str)
	]
	# The evidence references of both the friction and the passing action.
	evidence_references = references_for_entries(
		[
			friction_event,
			{"evidence_references": resolution_references},
		]
	)
	# The passing action's target, falling back to the friction target.
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

	Args:
		rollouts: The rollouts whose successful tool actions may resolve friction.
		observations: The candidate friction observations to match.
		evidence_index: Evidence entries keyed by reference for timestamps.

	Returns:
		Recovery observations for matched friction and passing actions.
	"""
	# Successful actions with usable timestamps, available to resolve friction.
	resolving_actions = []
	# Each successful ledger entry in any rollout may resolve friction.
	for rollout in rollouts:
		for ledger_value in rollout.get("tool_ledger", []):
			# The ledger record, checked to be a mapping.
			ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
			if ledger_entry.get("status") != "success":
				continue

			# The passing action's call and result references that are present.
			references = [
				reference
				for reference in (
					ledger_entry.get("call_reference"),
					ledger_entry.get("result_reference"),
				)
				if isinstance(reference, str)
			]
			# The earliest timestamp supported by the passing action's evidence.
			timestamp = earliest_timestamp(
				[{"evidence_references": references}], evidence_index
			)
			# The parsed time used to sort the actions; actions without one are skipped.
			parsed_timestamp = parse_timestamp(timestamp)
			if parsed_timestamp is not None:
				resolving_actions.append((parsed_timestamp, rollout, ledger_entry))

	resolving_actions.sort(key=lambda value: value[0])

	# The friction events that have a time, with their position in the input.
	friction_events = []
	# Each friction observation with a time can be paired; its position breaks ties.
	for index, event in enumerate(observations):
		if event["kind"] not in {
			"tool_failure",
			"correction",
			"rollback",
			"interruption",
		}:
			continue

		# A comparable time for deciding whether a passing action came later.
		friction_timestamp = parse_timestamp(event.get("timestamp"))
		if friction_timestamp is not None:
			friction_events.append((friction_timestamp, index, event))
	friction_events.sort(key=lambda value: (value[0], value[1]))
	# Recovery observations formed from one-to-one friction and action matches.
	recoveries = []
	# The positions of passing actions already paired with friction.
	used_resolutions = set()
	# Pair each friction event, earliest first, with at most one passing action.
	for friction_timestamp, _, friction_event in friction_events:
		# The friction target; events without one are skipped.
		friction_target = bounded_text(friction_event.get("target"), 280)
		if friction_target is None:
			continue

		# The friction event's descriptor, which may name its tool.
		friction_descriptor = friction_event.get("descriptor")
		# The tool named in the friction descriptor, which the passing action must match.
		friction_tool = (
			friction_descriptor.get("tool")
			if isinstance(friction_descriptor, dict)
			else None
		)
		# The first unpaired passing action after the friction with the same target and tool.
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

		# The passing action and its position in the sorted list.
		resolution_index, resolution = resolving_action
		used_resolutions.add(resolution_index)
		# The rollout and ledger entry needed to describe this recovery.
		_, rollout, ledger_entry = resolution
		recoveries.append(
			recovery_event(friction_event, rollout, ledger_entry, evidence_index)
		)

	return recoveries


def derive_observations(
	rollout: dict[str, object], evidence_index: dict[str, dict[str, object]]
) -> list[dict[str, object]]:
	"""Derive candidate, tool failure and verification gap observations from a rollout.

	Args:
		rollout: The extracted rollout with candidate and tool ledger records.
		evidence_index: Evidence entries keyed by reference.

	Returns:
		Unique observations up to the conversation event limit.
	"""
	# The retained observations in source order.
	observations = []
	# Kind-and-reference identities already included in the observations.
	seen = set()

	def add_observation(observation: dict[str, object]) -> None:
		"""Keep one observation per kind and evidence set within the event limit.

		Args:
			observation: The observation to add. It is skipped when it has no
				evidence references, repeats a kind and references already added,
				or would pass the event limit.
		"""
		# The observation's evidence references.
		references = tuple(observation["evidence_references"])
		# Two observations with the same kind and references count as duplicates.
		identity = (observation["kind"], references)
		if (
			not references
			or identity in seen
			or len(observations) >= MAX_EVENTS_PER_CONVERSATION
		):
			return

		seen.add(identity)
		observations.append(observation)

	# Each extracted candidate becomes an observation of its field's kind.
	for field_name, kind in CANDIDATE_FIELDS.items():
		for candidate_value in rollout.get("candidates", {}).get(field_name, []):
			add_observation(
				candidate_event(rollout, candidate_value, kind, evidence_index)
			)

	# Each failed or unknown tool action becomes an observation, unless it was
	# explicitly marked as an expected probe.
	for ledger_value in rollout.get("tool_ledger", []):
		# The ledger record, checked to be a mapping.
		ledger_entry = require_mapping(ledger_value, "rollout.tool_ledger[]")
		# The action's reported status.
		status = ledger_entry.get("status")
		# How the action was marked as an expected probe; only an explicit mark skips it.
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
	"""Summarise an observation using its kind and bounded target text.

	Args:
		event: The observation whose kind and target may appear in the summary.

	Returns:
		A short label with the target when one is available.
	"""
	# The event kind, extended with the friction source for a recovery.
	kind = event["kind"]
	if kind == "recovery":
		# The earlier friction kind that the recovery resolved, when known.
		source = event.get("source")
		if isinstance(source, str) and source:
			kind = f"{kind} from {source}"
	# The optional target text that makes the event summary specific.
	target = event.get("target")
	if isinstance(target, str) and target:
		return f"{kind}: {target}"

	return str(kind)


def limitation(
	kind: str, summary: str, references: Iterable[str] = ()
) -> dict[str, object]:
	"""Describe a limitation with its evidence links and confidence.

	Unavailable evidence gets high confidence; every other kind gets medium.

	Args:
		kind: The limitation type, including unavailable evidence.
		summary: The reason the conversation evidence is limited.
		references: Evidence links supporting this limitation.

	Returns:
		The limitation with its kind, summary, references and confidence.
	"""
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

	Args:
		conversation_id: The conversation identifier, or None when unavailable.
		rollouts: The extracted rollouts belonging to this conversation.
		evidence_index: Evidence entries keyed by reference.

	Returns:
		The conversation facet and the observations available for patterns.
	"""
	# All retained evidence mappings from the conversation's rollouts.
	all_evidence = []
	# Candidate and ledger observations before adding recoveries.
	base_observations = []
	# Collect each rollout's evidence records and observations.
	for rollout in rollouts:
		all_evidence.extend(
			entry for entry in rollout.get("evidence", []) if isinstance(entry, dict)
		)
		base_observations.extend(derive_observations(rollout, evidence_index))
	# Recoveries may use at most half of the event limit.
	max_recoveries = MAX_EVENTS_PER_CONVERSATION // 2
	# All recoveries found before applying the conversation event limit.
	recoveries = recovery_observations(rollouts, base_observations, evidence_index)
	# Recoveries retained within their share of the limit.
	kept_recoveries = recoveries[:max_recoveries]
	# Base observations left after reserving space for the retained recoveries.
	base_observations = base_observations[
		: MAX_EVENTS_PER_CONVERSATION - len(kept_recoveries)
	]
	# The complete bounded observation list used for the facet and patterns.
	all_observations = base_observations + kept_recoveries
	# The user messages that can supply the conversation's goal.
	authored_messages = [
		entry for entry in all_evidence if entry.get("kind") == "authored_user_message"
	]
	# The first authored message, if one was retained.
	goal_entry = authored_messages[0] if authored_messages else None
	# An observed goal or an explicit unavailable state.
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

	# The lifecycle and rollback records that show how the conversation ended.
	lifecycle_entries = [
		entry
		for entry in all_evidence
		if entry.get("kind") in {"lifecycle_event", "rollback_event"}
	]
	# The event types in those records.
	lifecycle_types = {entry.get("event_type") for entry in lifecycle_entries}
	# The outcome state follows the strongest retained lifecycle signal.
	if "task_complete" in lifecycle_types:
		# A completion event establishes a completed conversation.
		outcome_state = "completed"
	elif "thread_rolled_back" in lifecycle_types:
		# A rollback event establishes a rolled-back conversation.
		outcome_state = "rolled_back"
	elif "turn_aborted" in lifecycle_types:
		# An aborted turn establishes an interrupted conversation.
		outcome_state = "interrupted"
	elif any(rollout.get("activity_state") == "live" for rollout in rollouts):
		# A live rollout keeps the conversation active without a lifecycle outcome.
		outcome_state = "live"
	else:
		# No retained signal establishes a known outcome.
		outcome_state = "unknown"
	# References to the lifecycle records supporting the inferred outcome.
	outcome_references = [entry["reference"] for entry in lifecycle_entries]
	# The outcome and its confidence based on available lifecycle evidence.
	outcome = {
		"state": outcome_state,
		"evidence_references": outcome_references,
		"classification": outcome_state,
		"confidence": "high" if lifecycle_entries else "low",
	}

	# Observation kinds that appear in the conversation's friction summary.
	friction_kinds = {
		"tool_failure",
		"correction",
		"retry",
		"verification_gap",
		"interruption",
		"rollback",
	}
	# A summary of each friction observation.
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
	# A summary of each user correction or approach change.
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
	# A summary of each verification gap.
	verification_gaps = [
		{
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] == "verification_gap"
	]
	# A summary of each approach change.
	approach_changes = [
		{
			"summary": event_summary(event),
			"evidence_references": event["evidence_references"],
			"classification": event["classification"],
		}
		for event in all_observations
		if event["kind"] == "approach_change"
	]

	# Known limitations, starting with the deterministic classifier's limit.
	limitations = [
		limitation(
			"classifier",
			"Semantic labels are deterministic candidate classifications, not model judgements.",
		)
	]
	# Each rollout adds one limitation per unreadable item and one if it was cut short.
	for rollout in rollouts:
		for unavailable in rollout.get("unavailable", []):
			limitations.append(
				limitation(
					"unavailable",
					str(unavailable),
					rollout.get("uncertain_user_message_references", []),
				)
			)
		# Extractor bounds that may have omitted records or candidates.
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

	# The user turns from every rollout, in rollout order.
	turns = []
	for rollout in rollouts:
		turns.extend(derive_turns(rollout, evidence_index))
	# The references of every evidence record and kept observation.
	all_references = references_for_entries(
		[
			{"evidence_references": [entry["reference"] for entry in all_evidence]},
			*all_observations,
		]
	)
	# Each rollout's parsed start time, or None when it has none.
	start_timestamps = [
		parse_timestamp(rollout.get("start_timestamp")) for rollout in rollouts
	]
	# Each rollout's parsed end time, or None when it has none.
	end_timestamps = [
		parse_timestamp(rollout.get("end_timestamp")) for rollout in rollouts
	]
	# The start times that parsed, used for the conversation's first time.
	start_timestamps = [
		timestamp for timestamp in start_timestamps if timestamp is not None
	]
	# The end times that parsed, used for the conversation's last time.
	end_timestamps = [
		timestamp for timestamp in end_timestamps if timestamp is not None
	]
	# The bounded conversation record returned alongside its observations.
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
	"""Check descriptors, recovery pairing, pattern labels and event limits.

	The fixtures cover structural and unknown targets; one-to-one recovery after
	friction; unmatched targets and tools; recovery pattern labels; event limits;
	and successful actions without friction.
	"""
	# Small indexed evidence for structural and unknown descriptor checks.
	evidence_index = {
		"tool": {"reference": "tool", "timestamp": "2026-08-08T10:00:00Z"},
		"user": {"reference": "user", "timestamp": "2026-08-08T10:00:01Z"},
	}
	# A failed lint action with a structural executable target.
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
	# The descriptor built from the failed ledger action.
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
	# A candidate whose evidence has no matching structural tool record.
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

	# Dated call and result evidence for passing actions before and after friction.
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
	# Four friction kinds, four later matching successes and one unrelated success.
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
	# Observations produced from the recovery fixture; the facet itself is unused.
	_, recovery_observation_values = conversation_facet(
		"recovery-conversation", [recovery_rollout], recovery_evidence_index
	)
	# The recovery observations from that fixture.
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

	# Dated evidence for friction with no target or a different tool.
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
	# Friction that must remain unresolved despite later passing actions.
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
	# Observations from the unmatched-recovery fixture; the facet itself is unused.
	_, negative_recovery_observations = conversation_facet(
		"negative-recovery-conversation",
		[negative_recovery_rollout],
		negative_recovery_evidence_index,
	)
	assert not any(
		event["kind"] == "recovery" for event in negative_recovery_observations
	)

	from codex_insights_facets_patterns import build_patterns

	# Pattern output from the recovery fixture, including any repeated patterns.
	patterns, repeated_patterns = build_patterns(recovery_observation_values, {})
	# The patterns that describe recoveries.
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

	# Enough dated evidence for one observation in every event slot.
	base_evidence_index = {
		f"base-{index}": {
			"reference": f"base-{index}",
			"timestamp": f"2026-08-08T11:{index // 60:02d}:{index % 60:02d}Z",
		}
		for index in range(MAX_EVENTS_PER_CONVERSATION)
	}
	# A rollout whose corrections fill the event limit, with no recoveries.
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
	# Observations retained when base events use the full conversation limit.
	_, base_only_observations = conversation_facet(
		"base-only-conversation", [base_only_rollout], base_evidence_index
	)
	assert len(base_only_observations) == MAX_EVENTS_PER_CONVERSATION

	# A passing action without any friction that it could resolve.
	success_only_rollout = {
		**recovery_rollout,
		"tool_ledger": [recovery_rollout["tool_ledger"][2]],
		"candidates": {},
	}
	# Observations produced without friction, which cannot include recoveries.
	_, success_only_observations = conversation_facet(
		"success-only-conversation", [success_only_rollout], recovery_evidence_index
	)
	assert not any(event["kind"] == "recovery" for event in success_only_observations)


if __name__ == "__main__":
	run_selftest()

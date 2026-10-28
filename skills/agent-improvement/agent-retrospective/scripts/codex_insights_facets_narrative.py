#!/usr/bin/env python3
"""Build and validate the facet and narrative documents from a Codex extraction."""

from __future__ import annotations

import datetime
from pathlib import Path

from codex_insights_facets_common import (
	FACETS_SCHEMA_VERSION,
	MAX_FINDINGS,
	NARRATIVE_SCHEMA_VERSION,
	UTC,
	ProvenanceError,
	available_conversation_id,
	conversation_key,
	format_timestamp,
	require_count,
	require_mapping,
	serialise,
	validate_references,
)

from codex_insights_facets_observations import conversation_facet
from codex_insights_facets_patterns import build_patterns, layer_for_surface


def finding_owner(kind: str) -> str:
	"""Choose the owner named in a finding for an observation kind.

	Args:
		kind: The repeated observation's kind.

	Returns:
		The agent, configuration, or workflow owner.
	"""
	if kind in {"correction", "tool_failure"}:
		return "agent"
	if kind == "configuration_touch":
		return "configuration"
	if kind == "successful_behaviour":
		return "workflow"
	return "workflow"


def proposed_change(pattern: dict[str, object]) -> tuple[str, str, str]:
	"""Suggest a change or investigation for a repeated pattern.

	Args:
		pattern: The repeated pattern and any current configuration statuses.

	Returns:
		The proposed layer, target, and change or next investigation.
	"""
	# The observation kind determines which recommendation applies.
	kind = pattern["kind"]
	# The observed event text appears in the proposed change.
	observed = pattern["observed_pattern"]
	# Configuration statuses identify a surface that may already have guidance.
	statuses = pattern.get("configuration_statuses", [])
	if kind == "configuration_touch" and statuses:
		# The first inspected surface supplies the recommendation's target.
		status = statuses[0]
		# The named path is preferred over the surface token when available.
		path = (
			status.get("path") or status.get("surface") or "named configuration surface"
		)
		# The surface name determines the layer to change or investigate.
		layer = layer_for_surface(status.get("surface"))
		if status.get("status") == "missing":
			return (
				layer,
				str(path),
				f"Add guidance for {observed} to {path} after confirming its owning project.",
			)
		if status.get("status") == "already_remediated":
			return (
				layer,
				str(path),
				f"Do not add duplicate guidance; investigate why the observed behaviour bypassed {path}.",
			)
		if status.get("status") == "present_but_ignored":
			return (
				layer,
				str(path),
				f"Do not duplicate prose; investigate deterministic enforcement for the observed use of {path}.",
			)
		return (
			layer,
			str(path),
			f"Resolve access to {path} before choosing a configuration change.",
		)

	if kind == "successful_behaviour":
		return (
			"workflow",
			"team workflow",
			f"Standardise the successful bounded behaviour shown by {observed} and measure repeat success.",
		)
	if kind == "correction":
		return (
			"skill",
			"agent-retrospective workflow",
			f"Add a focused check for the corrected behaviour represented by {observed}.",
		)
	if kind in {"tool_failure", "verification_gap"}:
		return (
			"workflow",
			"verification step",
			f"Add a bounded verification step for {observed}, then measure whether the failure recurs.",
		)
	if kind == "retry":
		return (
			"workflow",
			"retry path",
			f"Document or instrument the bounded retry path represented by {observed}.",
		)
	if kind in {"interruption", "rollback"}:
		return (
			"workflow",
			"interruption recovery",
			f"Add a bounded recovery check for {observed}.",
		)
	return (
		"workflow",
		"approach-selection workflow",
		f"Investigate the approach change represented by {observed} before adding guidance.",
	)


def narrative_finding(pattern: dict[str, object]) -> dict[str, object]:
	"""Turn one repeated pattern into a proposed finding.

	Args:
		pattern: The repeated pattern with evidence and classification.

	Returns:
		A finding with frequency, evidence, limits, and a proposed action.
	"""
	# The recommendation names the layer, surface, and next action.
	layer, target, change = proposed_change(pattern)
	# The inspected surfaces determine the finding's configuration status.
	status = pattern.get("configuration_statuses", [])
	if not status:
		# No inspected surface can establish a current configuration state.
		current_configuration = {
			"status": "not_applicable",
			"surfaces": [],
		}
	elif len({entry.get("status") for entry in status}) == 1:
		# Matching surface statuses can be reported together.
		current_configuration = {
			"status": status[0].get("status"),
			"surfaces": status,
		}
	else:
		# Different surface statuses leave the overall state ambiguous.
		current_configuration = {"status": "ambiguous", "surfaces": status}

	# The pattern's limitations, plus one caveat about what the evidence cannot show.
	limitations = list(pattern.get("counterevidence_or_limitations", []))
	if pattern["kind"] == "successful_behaviour":
		limitations.append(
			"Successful tool status does not alone prove that the user accepted the result."
		)
	else:
		limitations.append(
			"The deterministic pass does not infer intent beyond the retained candidate evidence."
		)
	return {
		"finding_id": pattern["pattern_id"],
		"kind": pattern["kind"],
		"observed_pattern": pattern["observed_pattern"],
		"frequency": {
			"occurrences": pattern["occurrence_count"],
			"unique_conversations": pattern["unique_conversation_count"],
			"state": "repeated",
		},
		"time_span": pattern["time_span"],
		"diagnosis": pattern["classification"],
		"owner": finding_owner(pattern["kind"]),
		"consequence": f"The repeated pattern affects work represented by {pattern['observed_pattern']}.",
		"proposed_layer": layer,
		"proposed_target": target,
		"exact_change_or_next_investigation": change,
		"supporting_evidence": pattern["supporting_evidence"],
		"counterevidence_or_limitations": limitations,
		"current_configuration_status": current_configuration,
		"confidence": pattern["classification"]["confidence"],
	}


def make_facets(
	extraction_info: dict[str, object],
) -> dict[str, object]:
	"""Build conversation facets and patterns from a validated extraction.

	Args:
		extraction_info: The extraction binding, rollout index, and evidence index.

	Returns:
		The facet document with conversation facets, patterns, counts, and limits.
	"""
	# Indexed evidence is passed to each conversation facet builder.
	evidence_index = extraction_info["evidence_index"]
	# The extracted rollout records, which are grouped by conversation below.
	rollouts = extraction_info["rollout_index"]
	# Each key gathers the rollouts belonging to one conversation.
	by_conversation: dict[str, list[dict[str, object]]] = {}
	# Each rollout is attached to its conversation before facets are built.
	for rollout in rollouts.values():
		by_conversation.setdefault(conversation_key(rollout), []).append(rollout)

	# Conversation facets appear in conversation-key order.
	conversation_facets = []
	# Observations from all conversations feed the pattern builder.
	all_observations = []
	# Each conversation contributes one facet and its observations.
	for key, conversation_rollouts in sorted(by_conversation.items()):
		# The first rollout supplies the available conversation identifier.
		conversation_id = available_conversation_id(conversation_rollouts[0])
		# The facet builder returns both its document and pattern observations.
		facet, observations = conversation_facet(
			conversation_id, conversation_rollouts, evidence_index
		)
		conversation_facets.append(facet)
		# Each observation inherits the conversation's project path for surface checks.
		for observation in observations:
			observation["project_path"] = conversation_rollouts[0].get("project_path")
		all_observations.extend(observations)

	# Repeated surface checks share their result across matching observations.
	configuration_cache: dict[tuple[str, str, tuple[str, ...]], dict[str, object]] = {}
	# All patterns and the repeated subset populate the facet document.
	patterns, repeated_patterns = build_patterns(all_observations, configuration_cache)
	return {
		"schema_version": FACETS_SCHEMA_VERSION,
		"generated_at": format_timestamp(datetime.datetime.now(UTC)),
		"provenance": extraction_info["binding"],
		"counts": {
			"conversation_facet_count": len(conversation_facets),
			"pattern_count": len(patterns),
			"repeated_pattern_count": len(repeated_patterns),
		},
		"conversations": conversation_facets,
		"patterns": patterns,
		"repeated_patterns": repeated_patterns,
		"limitations": [
			"Patterns without two available conversation IDs remain illustrations, not recurrence findings.",
			"Current-configuration statuses are based on bounded reads of named surfaces only.",
		],
	}


def expected_binding(extraction_info: dict[str, object]) -> dict[str, object]:
	"""Get the extraction binding expected in a downstream document.

	Args:
		extraction_info: The validated extraction containing the binding.

	Returns:
		The extraction binding to compare with document provenance.
	"""
	return extraction_info["binding"]


def validate_binding(
	value: object,
	extraction_info: dict[str, object],
	location: str,
) -> None:
	"""Check that document provenance matches the extraction.

	Args:
		value: The facet or narrative document to check.
		extraction_info: The validated extraction with the expected binding.
		location: The document name used in validation errors.

	Raises:
		ProvenanceError: The document or binding is invalid or mismatched.
	"""
	# The document must be a mapping before its provenance can be checked.
	document = require_mapping(value, location)
	# The document's provenance contains the binding fields to compare.
	binding = require_mapping(document.get("provenance"), f"{location}.provenance")
	# The extraction supplies the authoritative values for those fields.
	expected = expected_binding(extraction_info)
	# Every expected field must agree with the document's provenance.
	for field_name in expected:
		if binding.get(field_name) != expected[field_name]:
			raise ProvenanceError(
				f"{location}.provenance.{field_name} does not match the extraction"
			)


def validate_facets(
	facets: dict[str, object], extraction_info: dict[str, object]
) -> None:
	"""Check facet provenance, recurrence, and evidence references.

	Args:
		facets: The facet document to validate.
		extraction_info: The extraction with expected binding and indexed evidence.

	Raises:
		ProvenanceError: A schema, binding, reference, or recurrence check fails.
	"""
	if facets.get("schema_version") != FACETS_SCHEMA_VERSION:
		raise ProvenanceError("unsupported facets schema version")
	validate_binding(facets, extraction_info, "facets")
	# References in facets and patterns must exist in this evidence index.
	evidence_index = extraction_info["evidence_index"]
	# Conversation facets must be an array before their entries are checked.
	conversations = facets.get("conversations")
	if not isinstance(conversations, list):
		raise ProvenanceError("facets.conversations must be an array")
	# Each conversation facet contributes references in several entry groups.
	for facet in conversations:
		# The facet must be a mapping before its fields are inspected.
		facet_value = require_mapping(facet, "facets.conversations[]")
		validate_references(
			facet_value.get("evidence_references", []), evidence_index, "facet"
		)
		# Each named entry group must be an array with valid evidence references.
		for field_name in (
			"turns",
			"friction_events",
			"successful_behaviours",
			"user_interventions",
			"verification_gaps",
			"approach_changes",
		):
			# Missing entry groups are treated as empty arrays.
			entries = facet_value.get(field_name, [])
			if not isinstance(entries, list):
				raise ProvenanceError(f"facet.{field_name} must be an array")
			# Each entry's references must point to indexed evidence.
			for entry in entries:
				# The entry must be a mapping before its references are read.
				entry_value = require_mapping(entry, f"facet.{field_name}[]")
				validate_references(
					entry_value.get("evidence_references", []),
					evidence_index,
					field_name,
				)

	# Each pattern must have valid references and credible recurrence evidence.
	for pattern in facets.get("patterns", []):
		# The pattern mapping supplies its references and recurrence state.
		pattern_value = require_mapping(pattern, "facets.patterns[]")
		validate_references(
			pattern_value.get("evidence_references", []), evidence_index, "pattern"
		)
		if pattern_value.get("recurrence_state") == "repeated":
			if pattern_value.get("unique_conversation_count", 0) < 2:
				raise ProvenanceError(
					"repeated pattern must cite at least two conversations"
				)
			# Supporting citations must identify at least two conversations.
			citations = pattern_value.get("supporting_evidence", [])
			# Citations that are objects with a non-empty conversation ID count
			# towards recurrence.
			citation_ids = {
				citation.get("conversation_id")
				for citation in citations
				if isinstance(citation, dict) and citation.get("conversation_id")
			}
			if len(citation_ids) < 2:
				raise ProvenanceError(
					"repeated pattern is missing unique conversation citations"
				)
			# Each supporting citation must refer to indexed evidence.
			for citation in citations:
				# The citation must be a mapping before its references are checked.
				citation_value = require_mapping(
					citation, "pattern.supporting_evidence[]"
				)
				validate_references(
					citation_value.get("evidence_references", []),
					evidence_index,
					"citation",
				)

	# The repeated subset may contain only patterns in the full list.
	for pattern in facets.get("repeated_patterns", []):
		if pattern not in facets.get("patterns", []):
			raise ProvenanceError(
				"facets.repeated_patterns contains an unknown pattern"
			)


def validate_narrative(
	narrative: dict[str, object],
	extraction_info: dict[str, object],
	facets: dict[str, object],
	facets_sha256: str,
) -> None:
	"""Check a narrative against its extraction and facet documents.

	Args:
		narrative: The narrative document to validate.
		extraction_info: The extraction with expected binding and indexed evidence.
		facets: The facet document whose pattern count is expected.
		facets_sha256: The expected hash of the facet document.

	Raises:
		ProvenanceError: A schema, binding, finding, or evidence check fails.
	"""
	if narrative.get("schema_version") != NARRATIVE_SCHEMA_VERSION:
		raise ProvenanceError("unsupported narrative schema version")
	validate_binding(narrative, extraction_info, "narrative")
	# Narrative provenance also binds the facet schema, hash, and pattern count.
	provenance = require_mapping(narrative.get("provenance"), "narrative.provenance")
	if provenance.get("facets_schema_version") != FACETS_SCHEMA_VERSION:
		raise ProvenanceError("narrative facets schema version does not match")
	if provenance.get("facets_sha256") != facets_sha256:
		raise ProvenanceError("narrative facets SHA-256 does not match")
	if provenance.get("facets_pattern_count") != facets.get("counts", {}).get(
		"pattern_count"
	):
		raise ProvenanceError("narrative facets pattern count does not match")

	# Finding citations must point to evidence from the extraction.
	evidence_index = extraction_info["evidence_index"]
	# Findings are limited by MAX_FINDINGS and must be an array.
	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise ProvenanceError("narrative.findings must be a bounded array")
	# Each finding needs at least two conversations and valid citations.
	for finding in findings:
		# The finding mapping supplies its frequency and evidence.
		finding_value = require_mapping(finding, "narrative.findings[]")
		# Frequency records the number of unique conversations.
		frequency = require_mapping(finding_value.get("frequency"), "finding.frequency")
		if (
			require_count(
				frequency.get("unique_conversations"),
				"finding.frequency.unique_conversations",
			)
			< 2
		):
			raise ProvenanceError(
				"narrative finding must cite at least two conversations"
			)
		# Supporting evidence must be an array of citations.
		supporting_evidence = finding_value.get("supporting_evidence")
		if not isinstance(supporting_evidence, list):
			raise ProvenanceError("finding.supporting_evidence must be an array")
		# The distinct conversations this finding cites.
		conversation_ids = set()
		# Each citation contributes an identifier and checked evidence references.
		for citation in supporting_evidence:
			# The citation must be a mapping before its fields are read.
			citation_value = require_mapping(citation, "finding.supporting_evidence[]")
			# Only non-empty string conversation identifiers count.
			conversation_id = citation_value.get("conversation_id")
			if isinstance(conversation_id, str) and conversation_id:
				conversation_ids.add(conversation_id)
			validate_references(
				citation_value.get("evidence_references", []),
				evidence_index,
				"finding citation",
			)
		if len(conversation_ids) < 2:
			raise ProvenanceError("finding must cite two unique conversation IDs")


def make_narrative(
	facets: dict[str, object], extraction_info: dict[str, object], facets_sha256: str
) -> dict[str, object]:
	"""Build a narrative from the facet document's repeated patterns.

	Args:
		facets: The validated facets with repeated patterns and pattern counts.
		extraction_info: The extraction binding for narrative provenance.
		facets_sha256: The hash binding this narrative to its facet document.

	Returns:
		The narrative with bounded findings, provenance, and limits.
	"""
	# Only repeated patterns can become narrative findings.
	repeated_patterns = facets.get("repeated_patterns", [])
	# Findings stop at MAX_FINDINGS and retain their pattern order.
	findings = [
		narrative_finding(pattern) for pattern in repeated_patterns[:MAX_FINDINGS]
	]
	return {
		"schema_version": NARRATIVE_SCHEMA_VERSION,
		"generated_at": format_timestamp(datetime.datetime.now(UTC)),
		"provenance": {
			**extraction_info["binding"],
			"facets_schema_version": FACETS_SCHEMA_VERSION,
			"facets_sha256": facets_sha256,
			"facets_pattern_count": facets.get("counts", {}).get("pattern_count"),
		},
		"findings": findings,
		"limitations": [
			"Only repeated patterns with at least two unique conversation citations become findings.",
			"The narrative does not replace direct review when bounded evidence is unavailable.",
		],
	}


def write_json(path: Path, value: dict[str, object]) -> None:
	"""Write a generated document as JSON, creating its parent directory.

	Args:
		path: The output file to create or replace.
		value: The document to serialise.
	"""
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(serialise(value), encoding="utf-8")

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
	"""Return a plain-language owner for one repeated observation."""
	if kind in {"correction", "tool_failure"}:
		return "agent"
	if kind == "configuration_touch":
		return "configuration"
	if kind == "successful_behaviour":
		return "workflow"
	return "workflow"


def proposed_change(pattern: dict[str, object]) -> tuple[str, str, str]:
	"""Return a bounded layer, target, and exact change or next investigation."""
	kind = pattern["kind"]
	observed = pattern["observed_pattern"]
	statuses = pattern.get("configuration_statuses", [])
	if kind == "configuration_touch" and statuses:
		status = statuses[0]
		path = (
			status.get("path") or status.get("surface") or "named configuration surface"
		)
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
			"codex-insights workflow",
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
	"""Convert one repeated facet pattern into the actionable finding contract."""
	layer, target, change = proposed_change(pattern)
	status = pattern.get("configuration_statuses", [])
	if not status:
		current_configuration = {
			"status": "not_applicable",
			"surfaces": [],
		}
	elif len({entry.get("status") for entry in status}) == 1:
		current_configuration = {
			"status": status[0].get("status"),
			"surfaces": status,
		}
	else:
		current_configuration = {"status": "ambiguous", "surfaces": status}

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
	"""Build the bounded facet document from one validated extraction."""
	evidence_index = extraction_info["evidence_index"]
	rollouts = extraction_info["rollout_index"]
	by_conversation: dict[str, list[dict[str, object]]] = {}
	for rollout in rollouts.values():
		by_conversation.setdefault(conversation_key(rollout), []).append(rollout)

	conversation_facets = []
	all_observations = []
	for key, conversation_rollouts in sorted(by_conversation.items()):
		conversation_id = available_conversation_id(conversation_rollouts[0])
		facet, observations = conversation_facet(
			conversation_id, conversation_rollouts, evidence_index
		)
		conversation_facets.append(facet)
		for observation in observations:
			observation["project_path"] = conversation_rollouts[0].get("project_path")
		all_observations.extend(observations)

	configuration_cache: dict[tuple[str, str, tuple[str, ...]], dict[str, object]] = {}
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
	"""Return the binding expected in a facet or narrative document."""
	return extraction_info["binding"]


def validate_binding(
	value: object,
	extraction_info: dict[str, object],
	location: str,
) -> None:
	"""Reject stale or mismatched provenance before downstream synthesis."""
	document = require_mapping(value, location)
	binding = require_mapping(document.get("provenance"), f"{location}.provenance")
	expected = expected_binding(extraction_info)
	for field_name in expected:
		if binding.get(field_name) != expected[field_name]:
			raise ProvenanceError(
				f"{location}.provenance.{field_name} does not match the extraction"
			)


def validate_facets(
	facets: dict[str, object], extraction_info: dict[str, object]
) -> None:
	"""Validate facet provenance, pattern recurrence, and all evidence references."""
	if facets.get("schema_version") != FACETS_SCHEMA_VERSION:
		raise ProvenanceError("unsupported facets schema version")
	validate_binding(facets, extraction_info, "facets")
	evidence_index = extraction_info["evidence_index"]
	conversations = facets.get("conversations")
	if not isinstance(conversations, list):
		raise ProvenanceError("facets.conversations must be an array")
	for facet in conversations:
		facet_value = require_mapping(facet, "facets.conversations[]")
		validate_references(
			facet_value.get("evidence_references", []), evidence_index, "facet"
		)
		for field_name in (
			"turns",
			"friction_events",
			"successful_behaviours",
			"user_interventions",
			"verification_gaps",
			"approach_changes",
		):
			entries = facet_value.get(field_name, [])
			if not isinstance(entries, list):
				raise ProvenanceError(f"facet.{field_name} must be an array")
			for entry in entries:
				entry_value = require_mapping(entry, f"facet.{field_name}[]")
				validate_references(
					entry_value.get("evidence_references", []),
					evidence_index,
					field_name,
				)

	for pattern in facets.get("patterns", []):
		pattern_value = require_mapping(pattern, "facets.patterns[]")
		validate_references(
			pattern_value.get("evidence_references", []), evidence_index, "pattern"
		)
		if pattern_value.get("recurrence_state") == "repeated":
			if pattern_value.get("unique_conversation_count", 0) < 2:
				raise ProvenanceError(
					"repeated pattern must cite at least two conversations"
				)
			citations = pattern_value.get("supporting_evidence", [])
			citation_ids = {
				citation.get("conversation_id")
				for citation in citations
				if isinstance(citation, dict) and citation.get("conversation_id")
			}
			if len(citation_ids) < 2:
				raise ProvenanceError(
					"repeated pattern is missing unique conversation citations"
				)
			for citation in citations:
				citation_value = require_mapping(
					citation, "pattern.supporting_evidence[]"
				)
				validate_references(
					citation_value.get("evidence_references", []),
					evidence_index,
					"citation",
				)

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
	"""Validate the actionable narrative contract and its two upstream bindings."""
	if narrative.get("schema_version") != NARRATIVE_SCHEMA_VERSION:
		raise ProvenanceError("unsupported narrative schema version")
	validate_binding(narrative, extraction_info, "narrative")
	provenance = require_mapping(narrative.get("provenance"), "narrative.provenance")
	if provenance.get("facets_schema_version") != FACETS_SCHEMA_VERSION:
		raise ProvenanceError("narrative facets schema version does not match")
	if provenance.get("facets_sha256") != facets_sha256:
		raise ProvenanceError("narrative facets SHA-256 does not match")
	if provenance.get("facets_pattern_count") != facets.get("counts", {}).get(
		"pattern_count"
	):
		raise ProvenanceError("narrative facets pattern count does not match")

	evidence_index = extraction_info["evidence_index"]
	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise ProvenanceError("narrative.findings must be a bounded array")
	for finding in findings:
		finding_value = require_mapping(finding, "narrative.findings[]")
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
		supporting_evidence = finding_value.get("supporting_evidence")
		if not isinstance(supporting_evidence, list):
			raise ProvenanceError("finding.supporting_evidence must be an array")
		conversation_ids = set()
		for citation in supporting_evidence:
			citation_value = require_mapping(citation, "finding.supporting_evidence[]")
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
	"""Build the decision-oriented narrative document from validated repeated patterns."""
	repeated_patterns = facets.get("repeated_patterns", [])
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
	"""Write one generated JSON artefact, creating its parent directory."""
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(serialise(value), encoding="utf-8")

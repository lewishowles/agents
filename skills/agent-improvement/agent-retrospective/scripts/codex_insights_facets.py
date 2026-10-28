#!/usr/bin/env python3
"""Classify bounded Codex evidence into facets and actionable findings."""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

from codex_insights_facets_common import (
	DEFAULT_EXTRACTION_PATH,
	DEFAULT_FACETS_PATH,
	DEFAULT_NARRATIVE_PATH,
	EXTRACTION_SCHEMA_VERSION,
	ProvenanceError,
	hash_bytes,
	load_json,
	require_mapping,
	require_string,
	validate_extraction,
)

from codex_insights_facets_narrative import (
	make_facets,
	make_narrative,
	proposed_change,
	validate_binding,
	validate_facets,
	validate_narrative,
	write_json,
)
from codex_insights_facets_patterns import (
	configuration_markers_for_pattern,
	configuration_status,
	run_selftest as run_patterns_selftest,
)

# Names re-exported here so codex_insights_render.py can import them from this module.
__all__ = (
	"ProvenanceError",
	"fixture_extraction",
	"hash_bytes",
	"load_json",
	"make_facets",
	"make_narrative",
	"require_mapping",
	"require_string",
	"validate_extraction",
	"validate_facets",
	"validate_narrative",
	"write_json",
)


def fixture_extraction(project_path: Path) -> dict[str, object]:
	"""Build a small extraction with repeated, bounded evidence for self-tests.

	Args:
		project_path: The project path recorded in the fixture rollouts.

	Returns:
		An extraction with two conversations, evidence, ledger entries and counts.
	"""

	def rollout(
		rollout_id: str, conversation_id: str, offset: int
	) -> dict[str, object]:
		"""Build one fixture rollout with a failed command followed by a pass.

		Args:
			rollout_id: The unique ID for this fixture rollout.
			conversation_id: The conversation ID recorded for this rollout.
			offset: The minute used for its evidence timestamps.

		Returns:
			The rollout, its evidence, candidates and command ledger.
		"""

		def reference(index: int) -> str:
			"""Build a reference to evidence within this rollout.

			Args:
				index: The evidence position within the rollout.

			Returns:
				The rollout ID followed by a numbered evidence reference.
			"""
			return f"{rollout_id}:r{index:06d}"

		# The ordered evidence for a request, failure, retry and completion.
		evidence = [
			{
				"reference": reference(0),
				"timestamp": f"2026-08-08T10:{offset:02d}:00Z",
				"kind": "authored_user_message",
				"authorship": "authored",
				"excerpt": "Please fix the repeated configuration check and verify it.",
			},
			{
				"reference": reference(1),
				"timestamp": f"2026-08-08T10:{offset:02d}:01Z",
				"kind": "assistant_message",
				"excerpt": "I will inspect the configuration.",
			},
			{
				"reference": reference(2),
				"timestamp": f"2026-08-08T10:{offset:02d}:02Z",
				"kind": "tool_call",
				"target": "cat AGENTS.md",
			},
			{
				"reference": reference(3),
				"timestamp": f"2026-08-08T10:{offset:02d}:03Z",
				"kind": "tool_result",
				"excerpt": "Process exited with code 1",
			},
			{
				"reference": reference(4),
				"timestamp": f"2026-08-08T10:{offset:02d}:04Z",
				"kind": "tool_call",
				"target": "cat AGENTS.md",
			},
			{
				"reference": reference(5),
				"timestamp": f"2026-08-08T10:{offset:02d}:05Z",
				"kind": "tool_result",
				"excerpt": "Process exited with code 0",
			},
			{
				"reference": reference(6),
				"timestamp": f"2026-08-08T10:{offset:02d}:06Z",
				"kind": "lifecycle_event",
				"event_type": "task_complete",
			},
		]
		# The candidate observations linked back to fixture evidence.
		candidate_values = {
			"approach_changes": [
				{
					"kind": "approach_change",
					"source": "authored_user_message",
					"evidence_references": [reference(0)],
				}
			],
			"configuration_touches": [
				{
					"kind": "configuration_touch",
					"target": "cat AGENTS.md",
					"evidence_references": [reference(2)],
				}
			],
			"corrections": [
				{
					"kind": "correction",
					"source": "authored_user_message",
					"evidence_references": [reference(0)],
				}
			],
			"interruptions": [],
			"retries": [
				{
					"kind": "retry",
					"target": "cat AGENTS.md",
					"evidence_references": [reference(2), reference(3), reference(4)],
				}
			],
			"rollbacks": [],
			"verification": [
				{
					"kind": "verification",
					"source": "failed_tool_event",
					"status": "failure",
					"evidence_references": [reference(2), reference(3)],
				}
			],
		}
		# The failed and successful command calls used by the fixture.
		ledger = [
			{
				"call_id": f"failure-{rollout_id}",
				"call_reference": reference(2),
				"result_reference": reference(3),
				"target": "cat AGENTS.md",
				"status": "failure",
				"status_source": "structured_exit_code",
				"exit_code": 1,
				"expected_probe": "not_expected",
			},
			{
				"call_id": f"success-{rollout_id}",
				"call_reference": reference(4),
				"result_reference": reference(5),
				"target": "cat AGENTS.md",
				"status": "success",
				"status_source": "structured_exit_code",
				"exit_code": 0,
				"expected_probe": "not_expected",
			},
		]
		return {
			"rollout_id": rollout_id,
			"conversation_id": conversation_id,
			"delegation_state": "parent",
			"subagent_role": None,
			"project_path": project_path.as_posix(),
			"start_timestamp": f"2026-08-08T10:{offset:02d}:00Z",
			"end_timestamp": f"2026-08-08T10:{offset:02d}:06Z",
			"activity_state": "elapsed",
			"uncertain_user_message_references": [],
			"tool_ledger": ledger,
			"evidence": evidence,
			"candidates": candidate_values,
			"truncation": {
				"candidate_count": 0,
				"evidence_count": 0,
				"tool_event_count": 0,
			},
			"unavailable": [],
		}

	# Separate conversations that exercise repeated-pattern grouping.
	rollouts = [
		rollout("rollout-a", "conversation-a", 10),
		rollout("rollout-b", "conversation-b", 20),
	]
	return {
		"schema_version": EXTRACTION_SCHEMA_VERSION,
		"window": {
			"since": "2026-08-08T10:00:00Z",
			"until": "2026-08-08T11:00:00Z",
			"end_utc_exclusive": "2026-08-08T11:00:00Z",
		},
		"provenance": {
			"input_sha256": "a" * 64,
			"source_hashes": ["b" * 64],
		},
		"counts": {
			"rollout_count": 2,
			"conversation_count": 2,
			"subagent_rollout_count": 0,
			"conversation_id_unavailable_count": 0,
			"subagent_role_unavailable_count": 0,
		},
		"rollouts": rollouts,
	}


def run_selftest() -> None:
	"""Check schema binding, facets, recurrence and configuration status.

	The checks also write facets to disk and read them back into the narrative,
	check the proposed change text for a missing configuration file, reject
	tampered extraction, facet and narrative bindings, then run the pattern
	builder's self-tests.

	Raises:
		AssertionError: A self-test check fails or tampered provenance is accepted.
	"""
	# The temporary workspace keeps self-test output away from user reports.
	with tempfile.TemporaryDirectory() as directory:
		# The workspace root for fixture inputs and derived documents.
		root = Path(directory)
		# The project directory whose configuration files are inspected.
		project = root / "project"
		project.mkdir()
		# A configuration observation expected to resolve to AGENTS.md.
		observed_pattern = "configuration_touch: cat AGENTS.md"
		# The marker used to recognise that observation in project guidance.
		marker = configuration_markers_for_pattern(
			"configuration_touch", observed_pattern
		)[0]
		# A distinct marker that must not match the AGENTS.md observation.
		other_marker = configuration_markers_for_pattern(
			"configuration_touch", "configuration_touch: cat WORKSPACE.md"
		)[0]
		assert marker == "cat AGENTS.md"
		assert marker != other_marker
		(project / "AGENTS.md").write_text(
			f"Read this project guidance.\nThe {marker} is documented here.\n",
			encoding="utf-8",
		)
		# The fixture extraction written for downstream validation.
		extraction_path = root / "latest.json"
		write_json(extraction_path, fixture_extraction(project))
		# The validated extraction and its provenance binding.
		extraction_info = validate_extraction(extraction_path)
		# The conversation facets derived from the fixture.
		facets = make_facets(extraction_info)
		validate_facets(facets, extraction_info)
		# The persisted facet document used to check disk round trips.
		facets_path = root / "latest-facets.json"
		write_json(facets_path, facets)
		# The SHA-256 digest of the facet file written to disk.
		facets_sha256 = hash_bytes(facets_path.read_bytes())
		# The facet document loaded back from disk.
		facets_from_disk = load_json(facets_path)
		validate_facets(facets_from_disk, extraction_info)
		# The written findings bound to the loaded facets and extraction.
		narrative = make_narrative(facets_from_disk, extraction_info, facets_sha256)
		validate_narrative(narrative, extraction_info, facets_from_disk, facets_sha256)

		assert len(facets["conversations"]) == 2
		assert all(
			facet["task_goal"]["evidence_references"]
			for facet in facets["conversations"]
		)
		assert all(facet["turns"] for facet in facets["conversations"])
		assert facets["repeated_patterns"]
		assert all(
			pattern["unique_conversation_count"] >= 2
			for pattern in facets["repeated_patterns"]
		)
		# The repeated configuration observation whose status is checked.
		agents_pattern = next(
			pattern
			for pattern in facets["repeated_patterns"]
			if pattern["kind"] == "configuration_touch"
		)
		assert len(agents_pattern["supporting_evidence"]) >= 2
		assert (
			agents_pattern["configuration_statuses"][0]["status"]
			== "already_remediated"
		)
		assert narrative["findings"]
		assert all(
			finding["frequency"]["unique_conversations"] >= 2
			for finding in narrative["findings"]
		)

		# The status of a configuration file absent from the fixture project.
		missing = configuration_status("cat WORKSPACE.md", project)
		assert missing["status"] == "missing"
		# The status of an observation naming more than one configuration file.
		ambiguous = configuration_status("cat AGENTS.md WORKSPACE.md", project)
		assert ambiguous["status"] == "ambiguous"
		# The status of an observed rule already covered by project guidance.
		remediated = configuration_status(
			"cat AGENTS.md", project, required_markers=("read this project guidance",)
		)
		assert remediated["status"] == "already_remediated"
		# The status when a present file lacks the required marker.
		ignored = configuration_status(
			"cat AGENTS.md", project, required_markers=(other_marker,)
		)
		assert ignored["status"] == "present_but_ignored"
		# A repeated pattern whose AGENTS.md is missing, used to check the proposed
		# change text.
		missing_pattern = {
			"kind": "configuration_touch",
			"observed_pattern": observed_pattern,
			"configuration_statuses": [
				{"status": "missing", "surface": "AGENTS.md", "path": "AGENTS.md"}
			],
		}
		# The proposed change text for that pattern.
		_, _, missing_change = proposed_change(missing_pattern)
		assert observed_pattern in missing_change
		assert "required behaviour" not in missing_change

		# A source document whose declared rollout total has been changed.
		tampered_extraction = json.loads(extraction_path.read_text(encoding="utf-8"))
		tampered_extraction["counts"]["rollout_count"] = 1
		# The file used to check rejection of changed source provenance.
		tampered_extraction_path = root / "tampered-extraction.json"
		write_json(tampered_extraction_path, tampered_extraction)
		try:
			validate_binding(
				facets, validate_extraction(tampered_extraction_path), "facets"
			)
		except ProvenanceError:
			pass
		else:
			raise AssertionError("tampered extraction provenance was accepted")

		# A facets document with an incorrect input hash.
		tampered_facets = json.loads(facets_path.read_text(encoding="utf-8"))
		tampered_facets["provenance"]["input_sha256"] = "c" * 64
		try:
			validate_facets(tampered_facets, extraction_info)
		except ProvenanceError:
			pass
		else:
			raise AssertionError("tampered facets provenance was accepted")

		# A narrative document with an incorrect extraction hash.
		tampered_narrative = json.loads(json.dumps(narrative))
		tampered_narrative["provenance"]["extraction_sha256"] = "d" * 64
		try:
			validate_narrative(
				tampered_narrative, extraction_info, facets_from_disk, facets_sha256
			)
		except ProvenanceError:
			pass
		else:
			raise AssertionError("tampered narrative provenance was accepted")

	run_patterns_selftest()
	print("codex_insights_facets selftest passed")


def parse_arguments() -> argparse.Namespace:
	"""Parse input and output paths or an isolated self-test request.

	Returns:
		The input path, the facets and narrative output paths, and the self-test flag.
	"""
	# The command line parser for report paths and the self-test mode.
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--input", type=Path, default=DEFAULT_EXTRACTION_PATH)
	parser.add_argument("--facets-output", type=Path, default=DEFAULT_FACETS_PATH)
	parser.add_argument("--narrative-output", type=Path, default=DEFAULT_NARRATIVE_PATH)
	parser.add_argument("--selftest", action="store_true")
	# The parsed command line values.
	arguments = parser.parse_args()
	# The self-test only runs with the default paths, so each path is compared
	# with its default.
	if arguments.selftest and any(
		path != default
		for path, default in (
			(arguments.input, DEFAULT_EXTRACTION_PATH),
			(arguments.facets_output, DEFAULT_FACETS_PATH),
			(arguments.narrative_output, DEFAULT_NARRATIVE_PATH),
		)
	):
		parser.error("--selftest cannot be combined with custom paths")
	return arguments


def main() -> None:
	"""Run the self-test or write validated facets and narrative findings."""
	# The selected mode and report paths.
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return

	# The source extraction and provenance binding for downstream reports.
	extraction_info = validate_extraction(arguments.input)
	# The derived conversation facets checked before they are written.
	facets = make_facets(extraction_info)
	validate_facets(facets, extraction_info)
	write_json(arguments.facets_output, facets)
	# The digest that binds the narrative to the written facet document.
	facets_sha256 = hash_bytes(arguments.facets_output.read_bytes())
	# The actionable findings derived from the validated facets.
	narrative = make_narrative(facets, extraction_info, facets_sha256)
	validate_narrative(narrative, extraction_info, facets, facets_sha256)
	write_json(arguments.narrative_output, narrative)
	print(
		f"Wrote {facets['counts']['conversation_facet_count']} conversation facets and "
		f"{len(narrative['findings'])} repeated findings"
	)


if __name__ == "__main__":
	main()

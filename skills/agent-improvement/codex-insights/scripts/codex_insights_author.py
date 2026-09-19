#!/usr/bin/env python3
"""Build a bounded, finding-specific evidence bundle for authored prose."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path

CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
USAGE_DATA_DIRECTORY = CODEX_HOME / "usage-data"
DEFAULT_EXTRACTION_PATH = USAGE_DATA_DIRECTORY / "latest.json"
DEFAULT_NARRATIVE_PATH = USAGE_DATA_DIRECTORY / "latest-narrative.json"
DEFAULT_BUNDLE_PATH = USAGE_DATA_DIRECTORY / "latest-authoring-bundle.json"
DEFAULT_DRAFT_PATH = USAGE_DATA_DIRECTORY / "latest-authored-draft.json"
DEFAULT_AUTHORED_PATH = USAGE_DATA_DIRECTORY / "latest-authored.json"
NARRATIVE_SCHEMA_VERSION = "2.0.0"
AUTHORING_BUNDLE_SCHEMA_VERSION = "1.0.0"
MAX_FINDINGS = 64
MAX_EXCERPTS_PER_FINDING = 8
MAX_EXCERPT_CHARS = 240
MAX_TOTAL_EXCERPT_CHARS = 1_200
MAX_BUNDLE_BYTES = 256 * 1024
# Shortest verbatim excerpt substring that counts as grounding evidence for a proposed change.
MIN_GROUNDING_QUOTE_CHARS = 40
# The only finding fields an authored draft is allowed to change from the narrative source.
AUTHORED_FIELDS = frozenset({"consequence", "exact_change_or_next_investigation"})
# Extra fields a draft finding may carry beyond the narrative's own fields.
DRAFT_METADATA_FIELDS = frozenset({"pattern_id", "quotes_used"})


class AuthoringError(ValueError):
	"""Raised when an authoring input is malformed or cannot be traced."""


def hash_bytes(value: bytes) -> str:
	"""Return the SHA-256 digest for one artefact byte sequence."""
	return hashlib.sha256(value).hexdigest()


def serialise(value: dict[str, object]) -> str:
	"""Serialise one generated document with stable key ordering."""
	return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def require_mapping(value: object, location: str) -> dict[str, object]:
	"""Require one JSON object at a schema location."""
	if not isinstance(value, dict):
		raise AuthoringError(f"{location} must be an object")

	return value


def require_string(value: object, location: str) -> str:
	"""Require one non-empty string at a schema location."""
	if not isinstance(value, str) or not value:
		raise AuthoringError(f"{location} must be a non-empty string")

	return value


def load_json(path: Path) -> tuple[dict[str, object], bytes]:
	"""Read one JSON object and retain its exact source bytes for hashing."""
	try:
		contents = path.read_bytes()
		value = json.loads(contents)
	except (OSError, UnicodeError, json.JSONDecodeError) as error:
		raise AuthoringError(f"cannot read JSON artefact {path}: {error}") from error

	return require_mapping(value, str(path)), contents


def evidence_index(extraction: dict[str, object]) -> dict[str, dict[str, object]]:
	"""Index retained extraction evidence and reject duplicate references."""
	rollouts = extraction.get("rollouts")
	if not isinstance(rollouts, list):
		raise AuthoringError("extraction.rollouts must be an array")

	indexed: dict[str, dict[str, object]] = {}
	for rollout_value in rollouts:
		rollout = require_mapping(rollout_value, "extraction.rollouts[]")
		evidence = rollout.get("evidence")
		if not isinstance(evidence, list):
			raise AuthoringError("rollout.evidence must be an array")

		for evidence_value in evidence:
			entry = require_mapping(evidence_value, "rollout.evidence[]")
			reference = require_string(entry.get("reference"), "evidence.reference")
			if reference in indexed:
				raise AuthoringError(f"duplicate evidence reference: {reference}")

			indexed[reference] = entry

	return indexed


def finding_references(finding: dict[str, object], location: str) -> list[str]:
	"""Return only the evidence references owned by one narrative finding."""
	references: list[str] = []

	supporting_evidence = finding.get("supporting_evidence", [])
	if not isinstance(supporting_evidence, list):
		raise AuthoringError(f"{location}.supporting_evidence must be an array")

	for citation_value in supporting_evidence:
		citation = require_mapping(citation_value, f"{location}.supporting_evidence[]")
		citation_references = citation.get("evidence_references")
		if not isinstance(citation_references, list):
			raise AuthoringError(
				f"{location}.supporting_evidence[].evidence_references must be an array"
			)

		references.extend(
			require_string(
				reference, f"{location}.supporting_evidence[].evidence_references[]"
			)
			for reference in citation_references
		)

	return sorted(set(references))


def bounded_excerpt(entry: dict[str, object]) -> str | None:
	"""Return one short evidence value without interpreting its content."""
	for field_name in ("excerpt", "target", "event_type"):
		value = entry.get(field_name)
		if isinstance(value, str) and value.strip():
			return value.strip()[:MAX_EXCERPT_CHARS]

	return None


def make_authoring_bundle(
	narrative: dict[str, object],
	extraction: dict[str, object],
	extraction_sha256: str | None = None,
	narrative_sha256: str | None = None,
) -> dict[str, object]:
	"""Build a deterministic bundle containing only each finding's own excerpts."""
	if narrative.get("schema_version") != NARRATIVE_SCHEMA_VERSION:
		raise AuthoringError("unsupported narrative schema version")

	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise AuthoringError("narrative.findings must be a bounded array")

	if extraction_sha256 is None:
		extraction_sha256 = ""
	if narrative_sha256 is None:
		narrative_sha256 = ""

	provenance = require_mapping(narrative.get("provenance"), "narrative.provenance")
	bound_extraction_sha256 = require_string(
		provenance.get("extraction_sha256"), "narrative.provenance.extraction_sha256"
	)
	if extraction_sha256 and bound_extraction_sha256 != extraction_sha256:
		raise AuthoringError("narrative extraction SHA-256 does not match latest.json")

	indexed_evidence = evidence_index(extraction)
	bundled_findings: dict[str, dict[str, object]] = {}
	for finding_index, finding_value in enumerate(findings):
		location = f"narrative.findings[{finding_index}]"
		finding = require_mapping(finding_value, location)
		finding_id = require_string(finding.get("finding_id"), f"{location}.finding_id")
		if finding_id in bundled_findings:
			raise AuthoringError(f"duplicate finding ID: {finding_id}")

		pattern_id_value = finding.get("pattern_id", finding_id)
		pattern_id = require_string(pattern_id_value, f"{location}.pattern_id")
		excerpts: list[dict[str, object]] = []
		total_chars = 0
		for reference in finding_references(finding, location):
			entry = indexed_evidence.get(reference)
			if entry is None:
				raise AuthoringError(
					f"{location} contains dangling evidence reference: {reference}"
				)

			text = bounded_excerpt(entry)
			if text is None or len(excerpts) >= MAX_EXCERPTS_PER_FINDING:
				continue

			remaining_chars = MAX_TOTAL_EXCERPT_CHARS - total_chars
			if remaining_chars <= 0:
				break

			text = text[:remaining_chars]
			if not text:
				continue

			excerpts.append(
				{
					"reference": reference,
					"kind": entry.get("kind"),
					"text": text,
				}
			)
			total_chars += len(text)

		bundled_findings[finding_id] = {
			"finding_id": finding_id,
			"pattern_id": pattern_id,
			"evidence_references": [excerpt["reference"] for excerpt in excerpts],
			"excerpts": excerpts,
		}

	bundle = {
		"schema_version": AUTHORING_BUNDLE_SCHEMA_VERSION,
		"provenance": {
			"extraction_sha256": extraction_sha256 or bound_extraction_sha256,
			"narrative_sha256": narrative_sha256,
			"finding_count": len(bundled_findings),
		},
		"findings": bundled_findings,
	}
	if len(serialise(bundle).encode("utf-8")) > MAX_BUNDLE_BYTES:
		raise AuthoringError("authoring bundle exceeds its byte bound")

	return bundle


def has_grounding_quote(
	proposed_change: object, bundle_finding: dict[str, object]
) -> bool:
	"""Return whether proposed_change quotes bundle_finding's own evidence verbatim."""
	if not isinstance(proposed_change, str):
		return False

	excerpts = bundle_finding.get("excerpts")
	if not isinstance(excerpts, list):
		return False

	for excerpt_value in excerpts:
		if not isinstance(excerpt_value, dict):
			continue

		excerpt_text = excerpt_value.get("text")
		if (
			not isinstance(excerpt_text, str)
			or len(excerpt_text) < MIN_GROUNDING_QUOTE_CHARS
		):
			continue

		last_start = len(excerpt_text) - MIN_GROUNDING_QUOTE_CHARS
		if any(
			excerpt_text[start : start + MIN_GROUNDING_QUOTE_CHARS] in proposed_change
			for start in range(last_start + 1)
		):
			return True

	return False


def validate_authored_finding(
	narrative_finding: dict[str, object],
	draft_finding: dict[str, object],
	bundle_finding: dict[str, object],
) -> None:
	"""Raise AuthoringError unless draft_finding's IDs, fields, and quote are all grounded."""
	finding_id = require_string(
		narrative_finding.get("finding_id"), "narrative finding_id"
	)
	bundle_finding_id = require_string(
		bundle_finding.get("finding_id"), "bundle finding_id"
	)
	if bundle_finding_id != finding_id:
		raise AuthoringError("bundle finding_id does not match narrative")

	pattern_id = require_string(bundle_finding.get("pattern_id"), "bundle pattern_id")
	if draft_finding.get("finding_id") != finding_id:
		raise AuthoringError("draft finding_id does not match narrative")
	if draft_finding.get("pattern_id") != pattern_id:
		raise AuthoringError("draft pattern_id does not match bundle")

	allowed_fields = set(narrative_finding) | DRAFT_METADATA_FIELDS
	if set(draft_finding) - allowed_fields:
		raise AuthoringError("draft contains an unexpected finding field")

	for field_name, narrative_value in narrative_finding.items():
		if field_name in AUTHORED_FIELDS:
			continue
		if (
			field_name not in draft_finding
			or draft_finding[field_name] != narrative_value
		):
			raise AuthoringError(f"draft changed immutable field: {field_name}")

	for field_name in AUTHORED_FIELDS:
		require_string(draft_finding.get(field_name), f"draft finding.{field_name}")

	quotes_used = draft_finding.get("quotes_used")
	if quotes_used is not None and (
		not isinstance(quotes_used, list)
		or any(not isinstance(quote, str) for quote in quotes_used)
	):
		raise AuthoringError("draft finding.quotes_used must be a string array")

	if not has_grounding_quote(
		draft_finding["exact_change_or_next_investigation"], bundle_finding
	):
		raise AuthoringError("draft finding has no grounded quote")


def _draft_finding_index(
	draft: dict[str, object],
) -> tuple[dict[str, dict[str, object]], set[str]]:
	"""Return draft findings indexed by finding_id, plus the set of IDs that repeat."""
	draft_findings = draft.get("findings")
	if not isinstance(draft_findings, list):
		return {}, set()

	indexed: dict[str, dict[str, object]] = {}
	duplicates: set[str] = set()
	for entry_value in draft_findings:
		if not isinstance(entry_value, dict):
			continue

		finding_id = entry_value.get("finding_id")
		if not isinstance(finding_id, str) or not finding_id:
			continue
		if finding_id in indexed:
			duplicates.add(finding_id)
			continue

		indexed[finding_id] = entry_value

	return indexed, duplicates


def validate_authored(
	narrative: dict[str, object],
	draft: dict[str, object] | None,
	bundle: dict[str, object] | None,
	narrative_sha256: str | None = None,
) -> dict[str, object]:
	"""Return every narrative finding with grounded draft prose merged in, else deterministic fallback."""
	if narrative_sha256 is None:
		narrative_sha256 = hash_bytes(serialise(narrative).encode("utf-8"))

	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise AuthoringError("narrative.findings must be a bounded array")

	narrative_findings: list[dict[str, object]] = []
	known_finding_ids: set[str] = set()
	for index, finding_value in enumerate(findings):
		finding = require_mapping(finding_value, f"narrative.findings[{index}]")
		finding_id = require_string(
			finding.get("finding_id"), f"narrative.findings[{index}].finding_id"
		)
		if finding_id in known_finding_ids:
			raise AuthoringError(f"duplicate narrative finding ID: {finding_id}")
		known_finding_ids.add(finding_id)
		narrative_findings.append(finding)

	output_findings: list[dict[str, object]] = []
	global_failure = not isinstance(draft, dict) or not isinstance(bundle, dict)
	draft_index: dict[str, dict[str, object]] = {}
	draft_duplicates: set[str] = set()
	bundle_findings: dict[str, object] = {}
	if not global_failure:
		draft_hash = draft.get("narrative_sha256")
		bundle_provenance = bundle.get("provenance")
		bundle_hash = (
			bundle_provenance.get("narrative_sha256")
			if isinstance(bundle_provenance, dict)
			else None
		)
		global_failure = (
			draft_hash != narrative_sha256 or bundle_hash != narrative_sha256
		)

		if not global_failure:
			draft_index, draft_duplicates = _draft_finding_index(draft)
			raw_bundle_findings = bundle.get("findings")
			if not isinstance(raw_bundle_findings, dict):
				global_failure = True
			else:
				bundle_findings = raw_bundle_findings

	for narrative_finding in narrative_findings:
		accepted = False
		draft_finding = None
		if not global_failure:
			finding_id = narrative_finding["finding_id"]
			if finding_id not in draft_duplicates:
				draft_finding = draft_index.get(finding_id)

		if draft_finding is not None:
			bundle_finding = bundle_findings.get(narrative_finding["finding_id"])
			if isinstance(bundle_finding, dict):
				try:
					validate_authored_finding(
						narrative_finding, draft_finding, bundle_finding
					)
				except AuthoringError:
					pass
				else:
					accepted = True

		output_finding = deepcopy(narrative_finding)
		if accepted:
			output_finding["consequence"] = draft_finding["consequence"]
			output_finding["exact_change_or_next_investigation"] = draft_finding[
				"exact_change_or_next_investigation"
			]
		output_finding["authored"] = accepted
		output_findings.append(output_finding)

	authored = deepcopy(narrative)
	authored["findings"] = output_findings
	authored["narrative_sha256"] = narrative_sha256
	return authored


def write_json(path: Path, value: dict[str, object]) -> None:
	"""Write one generated JSON artefact, creating its parent directory."""
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(serialise(value), encoding="utf-8")


def fixture_documents() -> tuple[dict[str, object], dict[str, object]]:
	"""Build two findings with isolated evidence for the authoring self-test."""
	evidence = []
	for rollout_id, finding_name in (("rollout-a", "first"), ("rollout-b", "second")):
		for index in range(10):
			evidence.append(
				{
					"reference": f"{rollout_id}:r{index:06d}",
					"kind": "assistant_message",
					"excerpt": (
						f"Evidence for {finding_name} finding, item {index}; "
						f"{finding_name}-specific retained behaviour evidence."
					),
				}
			)

	extraction = {
		"schema_version": "2.0.0",
		"rollouts": [
			{"rollout_id": "rollout-a", "evidence": evidence[:10]},
			{"rollout_id": "rollout-b", "evidence": evidence[10:]},
		],
	}
	narrative = {
		"schema_version": NARRATIVE_SCHEMA_VERSION,
		"provenance": {"extraction_sha256": "e" * 64},
		"findings": [
			{
				"finding_id": "finding-first",
				"kind": "repeated_failure",
				"observed_pattern": "the first repeated behaviour",
				"frequency": {"occurrences": 3, "unique_conversations": 2},
				"time_span": {"start": "2026-08-01", "end": "2026-08-02"},
				"diagnosis": {"summary": "first diagnosis"},
				"owner": "workflow",
				"consequence": "The first deterministic consequence.",
				"proposed_layer": "skill",
				"proposed_target": "first target",
				"exact_change_or_next_investigation": "The first deterministic change.",
				"supporting_evidence": [
					{
						"evidence_references": [
							f"rollout-a:r{index:06d}" for index in range(10)
						]
					}
				],
				"counterevidence_or_limitations": ["first limitation"],
				"current_configuration_status": {"status": "missing"},
				"confidence": 0.8,
			},
			{
				"finding_id": "finding-second",
				"kind": "repeated_correction",
				"observed_pattern": "the second repeated behaviour",
				"frequency": {"occurrences": 4, "unique_conversations": 2},
				"time_span": {"start": "2026-08-03", "end": "2026-08-04"},
				"diagnosis": {"summary": "second diagnosis"},
				"owner": "configuration",
				"consequence": "The second deterministic consequence.",
				"proposed_layer": "hook",
				"proposed_target": "second target",
				"exact_change_or_next_investigation": "The second deterministic change.",
				"supporting_evidence": [
					{
						"evidence_references": [
							f"rollout-b:r{index:06d}" for index in range(10)
						]
					}
				],
				"counterevidence_or_limitations": ["second limitation"],
				"current_configuration_status": {"status": "present"},
				"confidence": 0.9,
			},
		],
	}
	return narrative, extraction


def validation_fixture_draft(
	narrative: dict[str, object],
	bundle: dict[str, object],
	narrative_sha256: str,
) -> dict[str, object]:
	"""Build a draft whose findings quote their own bundle excerpt, so validation accepts each one."""
	draft_findings: list[dict[str, object]] = []
	bundle_findings = bundle["findings"]
	for narrative_finding in narrative["findings"]:
		finding_id = narrative_finding["finding_id"]
		bundle_finding = bundle_findings[finding_id]
		quote = bundle_finding["excerpts"][0]["text"]
		draft_finding = deepcopy(narrative_finding)
		draft_finding["pattern_id"] = bundle_finding["pattern_id"]
		draft_finding["quotes_used"] = [quote]
		draft_finding["consequence"] = f"Grounded consequence: {quote}"
		draft_finding["exact_change_or_next_investigation"] = (
			f"Apply the change shown by this evidence: {quote}"
		)
		draft_findings.append(draft_finding)

	return {
		"narrative_sha256": narrative_sha256,
		"findings": draft_findings,
	}


def assert_fallback_findings(
	authored: dict[str, object], narrative: dict[str, object]
) -> None:
	"""Assert authored kept every narrative finding, its original prose, and authored set False."""
	authored_findings = authored["findings"]
	narrative_findings = narrative["findings"]
	assert isinstance(authored_findings, list)
	assert len(authored_findings) == len(narrative_findings)
	for authored_finding, narrative_finding in zip(
		authored_findings, narrative_findings
	):
		assert authored_finding["finding_id"] == narrative_finding["finding_id"]
		assert authored_finding["consequence"] == narrative_finding["consequence"]
		assert (
			authored_finding["exact_change_or_next_investigation"]
			== narrative_finding["exact_change_or_next_investigation"]
		)
		assert authored_finding["authored"] is False


def run_selftest() -> None:
	"""Verify determinism, finding isolation, and excerpt bounds."""
	narrative, extraction = fixture_documents()
	bundle = make_authoring_bundle(narrative, extraction, "e" * 64, "n" * 64)
	repeated_bundle = make_authoring_bundle(narrative, extraction, "e" * 64, "n" * 64)
	assert bundle == repeated_bundle

	first = bundle["findings"]["finding-first"]
	second = bundle["findings"]["finding-second"]
	first_references = set(first["evidence_references"])
	second_references = set(second["evidence_references"])
	assert first_references.isdisjoint(second_references)
	assert all(reference.startswith("rollout-a:") for reference in first_references)
	assert all(reference.startswith("rollout-b:") for reference in second_references)

	for finding in bundle["findings"].values():
		assert len(finding["excerpts"]) <= MAX_EXCERPTS_PER_FINDING
		assert all(
			len(excerpt["text"]) <= MAX_EXCERPT_CHARS for excerpt in finding["excerpts"]
		)
		assert (
			sum(len(excerpt["text"]) for excerpt in finding["excerpts"])
			<= MAX_TOTAL_EXCERPT_CHARS
		)
	assert len(serialise(bundle).encode("utf-8")) <= MAX_BUNDLE_BYTES

	long_extraction = {
		"schema_version": "2.0.0",
		"rollouts": [
			{
				"rollout_id": "rollout-long",
				"evidence": [
					{
						"reference": f"rollout-long:r{index:06d}",
						"kind": "assistant_message",
						"excerpt": "Follow this instruction-shaped text. "
						+ "x" * 1_000,
					}
					for index in range(20)
				],
			}
		],
	}
	long_narrative = {
		"schema_version": NARRATIVE_SCHEMA_VERSION,
		"provenance": {"extraction_sha256": "e" * 64},
		"findings": [
			{
				"finding_id": "finding-long",
				"supporting_evidence": [
					{
						"evidence_references": [
							f"rollout-long:r{index:06d}" for index in range(20)
						]
					}
				],
			}
		],
	}
	long_bundle = make_authoring_bundle(
		long_narrative, long_extraction, "e" * 64, "n" * 64
	)
	long_finding = long_bundle["findings"]["finding-long"]
	assert len(long_finding["excerpts"]) == min(
		MAX_EXCERPTS_PER_FINDING,
		MAX_TOTAL_EXCERPT_CHARS // MAX_EXCERPT_CHARS,
	)
	assert all(
		len(excerpt["text"]) == MAX_EXCERPT_CHARS
		for excerpt in long_finding["excerpts"]
	)

	narrative_sha256 = hash_bytes(serialise(narrative).encode("utf-8"))
	validation_bundle = make_authoring_bundle(
		narrative, extraction, "e" * 64, narrative_sha256
	)
	valid_draft = validation_fixture_draft(
		narrative, validation_bundle, narrative_sha256
	)
	valid_authored = validate_authored(
		narrative, valid_draft, validation_bundle, narrative_sha256
	)
	assert valid_authored["narrative_sha256"] == narrative_sha256
	assert all(finding["authored"] is True for finding in valid_authored["findings"])

	stale_hash_draft = deepcopy(valid_draft)
	stale_hash_draft["narrative_sha256"] = "s" * 64
	assert_fallback_findings(
		validate_authored(
			narrative, stale_hash_draft, validation_bundle, narrative_sha256
		),
		narrative,
	)

	id_mismatch_draft = deepcopy(valid_draft)
	id_mismatch_draft["findings"][0]["finding_id"] = "finding-mismatch"
	id_mismatch_authored = validate_authored(
		narrative, id_mismatch_draft, validation_bundle, narrative_sha256
	)
	assert id_mismatch_authored["findings"][0]["authored"] is False
	assert id_mismatch_authored["findings"][1]["authored"] is True

	immutable_change_draft = deepcopy(valid_draft)
	immutable_change_draft["findings"][0]["owner"] = "tampered-owner"
	immutable_change_authored = validate_authored(
		narrative, immutable_change_draft, validation_bundle, narrative_sha256
	)
	assert immutable_change_authored["findings"][0]["authored"] is False
	assert immutable_change_authored["findings"][1]["authored"] is True

	pattern_id_mismatch_draft = deepcopy(valid_draft)
	pattern_id_mismatch_draft["findings"][0]["pattern_id"] = "pattern-mismatch"
	pattern_id_mismatch_authored = validate_authored(
		narrative, pattern_id_mismatch_draft, validation_bundle, narrative_sha256
	)
	assert pattern_id_mismatch_authored["findings"][0]["authored"] is False
	assert pattern_id_mismatch_authored["findings"][1]["authored"] is True

	absent_quote_draft = deepcopy(valid_draft)
	absent_quote_draft["findings"][0]["exact_change_or_next_investigation"] = (
		"This proposed change has no retained evidence quote."
	)
	absent_quote_authored = validate_authored(
		narrative, absent_quote_draft, validation_bundle, narrative_sha256
	)
	assert absent_quote_authored["findings"][0]["authored"] is False
	assert absent_quote_authored["findings"][1]["authored"] is True

	cross_finding_quote_draft = deepcopy(valid_draft)
	cross_finding_quote = validation_bundle["findings"]["finding-second"]["excerpts"][
		0
	]["text"]
	cross_finding_quote_draft["findings"][0]["exact_change_or_next_investigation"] = (
		f"Use this unrelated evidence: {cross_finding_quote}"
	)
	cross_finding_quote_authored = validate_authored(
		narrative, cross_finding_quote_draft, validation_bundle, narrative_sha256
	)
	assert cross_finding_quote_authored["findings"][0]["authored"] is False
	assert cross_finding_quote_authored["findings"][1]["authored"] is True

	assert_fallback_findings(
		validate_authored(narrative, None, validation_bundle, narrative_sha256),
		narrative,
	)

	print("codex_insights_author selftest passed")


def parse_arguments() -> argparse.Namespace:
	"""Parse bounded input/output paths or the isolated self-test request."""
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--input",
		"--extraction",
		dest="input",
		type=Path,
		default=DEFAULT_EXTRACTION_PATH,
	)
	parser.add_argument(
		"--narrative",
		"--narrative-input",
		dest="narrative",
		type=Path,
		default=DEFAULT_NARRATIVE_PATH,
	)
	parser.add_argument(
		"--output",
		"--bundle-output",
		dest="output",
		type=Path,
		default=DEFAULT_BUNDLE_PATH,
	)
	parser.add_argument(
		"--bundle-input",
		type=Path,
		default=DEFAULT_BUNDLE_PATH,
	)
	parser.add_argument(
		"--draft",
		"--draft-input",
		dest="draft",
		type=Path,
		default=DEFAULT_DRAFT_PATH,
	)
	parser.add_argument(
		"--authored-output",
		type=Path,
		default=DEFAULT_AUTHORED_PATH,
	)
	parser.add_argument(
		"--validate",
		"--validate-authored",
		dest="validate",
		action="store_true",
		help="validate the authored draft and write deterministic fallbacks",
	)
	parser.add_argument("--selftest", action="store_true")
	arguments = parser.parse_args()
	if arguments.selftest and any(
		path != default
		for path, default in (
			(arguments.input, DEFAULT_EXTRACTION_PATH),
			(arguments.narrative, DEFAULT_NARRATIVE_PATH),
			(arguments.output, DEFAULT_BUNDLE_PATH),
			(arguments.bundle_input, DEFAULT_BUNDLE_PATH),
			(arguments.draft, DEFAULT_DRAFT_PATH),
			(arguments.authored_output, DEFAULT_AUTHORED_PATH),
		)
	):
		parser.error("--selftest cannot be combined with custom paths")
	if arguments.selftest and arguments.validate:
		parser.error("--selftest cannot be combined with --validate")

	return arguments


def main() -> None:
	"""Build the authoring bundle, or validate an authored draft into a fallback-safe artefact."""
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return

	if arguments.validate:
		narrative, narrative_bytes = load_json(arguments.narrative)
		try:
			bundle, _ = load_json(arguments.bundle_input)
		except AuthoringError:
			bundle = None
		try:
			draft, _ = load_json(arguments.draft)
		except AuthoringError:
			draft = None
		authored = validate_authored(
			narrative,
			draft,
			bundle,
			hash_bytes(narrative_bytes),
		)
		write_json(arguments.authored_output, authored)
		print(f"Wrote authored findings for {len(authored['findings'])} findings")
		return

	extraction, extraction_bytes = load_json(arguments.input)
	narrative, narrative_bytes = load_json(arguments.narrative)
	bundle = make_authoring_bundle(
		narrative,
		extraction,
		hash_bytes(extraction_bytes),
		hash_bytes(narrative_bytes),
	)
	write_json(arguments.output, bundle)
	print(f"Wrote authoring bundle for {len(bundle['findings'])} findings")


if __name__ == "__main__":
	main()

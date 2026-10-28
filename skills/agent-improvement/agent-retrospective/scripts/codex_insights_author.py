#!/usr/bin/env python3
"""Build a bounded, finding-specific evidence bundle for authored prose."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path

# The Codex home directory, taken from CODEX_HOME or defaulting to ~/.codex.
CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
# Directory holding the latest extraction, narrative, and authored outputs.
USAGE_DATA_DIRECTORY = CODEX_HOME / "usage-data"
# Default source for retained rollout evidence.
DEFAULT_EXTRACTION_PATH = USAGE_DATA_DIRECTORY / "latest.json"
# Default source for narrative findings.
DEFAULT_NARRATIVE_PATH = USAGE_DATA_DIRECTORY / "latest-narrative.json"
# Default destination for the evidence bundle.
DEFAULT_BUNDLE_PATH = USAGE_DATA_DIRECTORY / "latest-authoring-bundle.json"
# Default source for prose drafted from the bundle.
DEFAULT_DRAFT_PATH = USAGE_DATA_DIRECTORY / "latest-authored-draft.json"
# Default destination for validated authored findings.
DEFAULT_AUTHORED_PATH = USAGE_DATA_DIRECTORY / "latest-authored.json"
# Narrative format accepted by the bundle builder.
NARRATIVE_SCHEMA_VERSION = "2.0.0"
# Format written for finding-specific evidence bundles.
AUTHORING_BUNDLE_SCHEMA_VERSION = "1.0.0"
# Maximum number of findings accepted from one narrative.
MAX_FINDINGS = 64
# Maximum number of retained excerpts for each finding.
MAX_EXCERPTS_PER_FINDING = 8
# Maximum character count for one retained excerpt.
MAX_EXCERPT_CHARS = 240
# Maximum combined excerpt character count for one finding.
MAX_TOTAL_EXCERPT_CHARS = 1_200
# Maximum UTF-8 byte size of the serialised bundle.
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
	"""Return the SHA-256 digest for one artefact byte sequence.

	Args:
		value: The exact artefact bytes to hash.

	Returns:
		The hexadecimal SHA-256 digest.
	"""
	return hashlib.sha256(value).hexdigest()


def serialise(value: dict[str, object]) -> str:
	"""Serialise one generated document with stable key ordering.

	Args:
		value: The document to write as JSON.

	Returns:
		Indented JSON with a trailing newline.
	"""
	return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def require_mapping(value: object, location: str) -> dict[str, object]:
	"""Require one JSON object at a schema location.

	Args:
		value: The value to check.
		location: The location named in a validation error.

	Returns:
		The validated object.

	Raises:
		AuthoringError: The value is not an object.
	"""
	if not isinstance(value, dict):
		raise AuthoringError(f"{location} must be an object")

	return value


def require_string(value: object, location: str) -> str:
	"""Require one non-empty string at a schema location.

	Args:
		value: The value to check.
		location: The location named in a validation error.

	Returns:
		The validated string.

	Raises:
		AuthoringError: The value is not a non-empty string.
	"""
	if not isinstance(value, str) or not value:
		raise AuthoringError(f"{location} must be a non-empty string")

	return value


def load_json(path: Path) -> tuple[dict[str, object], bytes]:
	"""Read one JSON object and retain its exact source bytes for hashing.

	Args:
		path: The JSON artefact to read.

	Returns:
		The decoded object and its original bytes.

	Raises:
		AuthoringError: The file cannot be read or does not contain a JSON object.
	"""
	try:
		# Original bytes used to bind later outputs to this exact input.
		contents = path.read_bytes()
		# Decoded document checked against the expected top-level shape.
		value = json.loads(contents)
	except (OSError, UnicodeError, json.JSONDecodeError) as error:
		raise AuthoringError(f"cannot read JSON artefact {path}: {error}") from error

	return require_mapping(value, str(path)), contents


def evidence_index(extraction: dict[str, object]) -> dict[str, dict[str, object]]:
	"""Index retained extraction evidence and reject duplicate references.

	Args:
		extraction: The extraction document containing rollout evidence.

	Returns:
		Evidence entries keyed by their reference.

	Raises:
		AuthoringError: Rollout evidence has the wrong shape or repeats a reference.
	"""
	# Rollout records whose evidence is available for authoring.
	rollouts = extraction.get("rollouts")
	if not isinstance(rollouts, list):
		raise AuthoringError("extraction.rollouts must be an array")

	# Unique evidence entries available for finding-specific lookup.
	indexed: dict[str, dict[str, object]] = {}
	# Each rollout supplies a separate group of retained evidence.
	for rollout_value in rollouts:
		# One extraction rollout checked before its evidence is indexed.
		rollout = require_mapping(rollout_value, "extraction.rollouts[]")
		# Retained evidence entries belonging to this rollout.
		evidence = rollout.get("evidence")
		if not isinstance(evidence, list):
			raise AuthoringError("rollout.evidence must be an array")

		# Each evidence value becomes one reference-keyed entry.
		for evidence_value in evidence:
			# One evidence object with a unique reference.
			entry = require_mapping(evidence_value, "rollout.evidence[]")
			# Key used by narrative findings to cite this entry.
			reference = require_string(entry.get("reference"), "evidence.reference")
			if reference in indexed:
				raise AuthoringError(f"duplicate evidence reference: {reference}")

			indexed[reference] = entry

	return indexed


def finding_references(finding: dict[str, object], location: str) -> list[str]:
	"""Return only the evidence references owned by one narrative finding.

	Args:
		finding: The narrative finding whose citations are inspected.
		location: The finding location named in validation errors.

	Returns:
		Sorted, unique evidence references cited by the finding.

	Raises:
		AuthoringError: A citation or reference has the wrong shape.
	"""
	# References gathered from every supporting citation for this finding.
	references: list[str] = []

	# Supporting citations supplied by the narrative, if any.
	supporting_evidence = finding.get("supporting_evidence", [])
	if not isinstance(supporting_evidence, list):
		raise AuthoringError(f"{location}.supporting_evidence must be an array")

	# Each citation contributes references owned by this finding.
	for citation_value in supporting_evidence:
		# One citation whose evidence references belong to this finding.
		citation = require_mapping(citation_value, f"{location}.supporting_evidence[]")
		# References listed inside the current citation.
		citation_references = citation.get("evidence_references")
		if not isinstance(citation_references, list):
			raise AuthoringError(
				f"{location}.supporting_evidence[].evidence_references must be an array"
			)

		# Each reference value is checked before it joins this finding's list.
		references.extend(
			require_string(
				reference, f"{location}.supporting_evidence[].evidence_references[]"
			)
			for reference in citation_references
		)

	return sorted(set(references))


def bounded_excerpt(entry: dict[str, object]) -> str | None:
	"""Return one short evidence value without interpreting its content.

	Args:
		entry: The retained evidence entry to excerpt.

	Returns:
		The first non-blank excerpt, target, or event type, trimmed to the
		character limit; otherwise None.
	"""
	# Candidate fields are tried in preferred order.
	for field_name in ("excerpt", "target", "event_type"):
		# Candidate text from the current preferred evidence field.
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
	"""Build a deterministic bundle containing only each finding's own excerpts.

	Args:
		narrative: The findings and citations that choose evidence.
		extraction: The retained rollout evidence available for citation.
		extraction_sha256: The extraction digest to check and record, if supplied.
		narrative_sha256: The narrative digest to record, if supplied.

	Returns:
		A size-limited bundle of excerpts grouped by finding ID.

	Raises:
		AuthoringError: The inputs are malformed, citations cannot be resolved,
			or the serialised bundle exceeds its byte limit.
	"""
	if narrative.get("schema_version") != NARRATIVE_SCHEMA_VERSION:
		raise AuthoringError("unsupported narrative schema version")

	# Narrative findings, at most MAX_FINDINGS of them.
	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise AuthoringError("narrative.findings must be a bounded array")

	if extraction_sha256 is None:
		# Empty digest allows the narrative's extraction digest to supply provenance.
		extraction_sha256 = ""
	if narrative_sha256 is None:
		# Empty digest records that no narrative hash was supplied.
		narrative_sha256 = ""

	# Narrative provenance used to bind citations to their extraction.
	provenance = require_mapping(narrative.get("provenance"), "narrative.provenance")
	# Extraction digest already recorded in the narrative.
	bound_extraction_sha256 = require_string(
		provenance.get("extraction_sha256"), "narrative.provenance.extraction_sha256"
	)
	if extraction_sha256 and bound_extraction_sha256 != extraction_sha256:
		raise AuthoringError("narrative extraction SHA-256 does not match latest.json")

	# Retained evidence available under unique reference keys.
	indexed_evidence = evidence_index(extraction)
	# Bundle entries keyed by the narrative finding ID.
	bundled_findings: dict[str, dict[str, object]] = {}
	# Each finding index and value identify one narrative entry to bundle.
	for finding_index, finding_value in enumerate(findings):
		# Location of this finding for precise validation errors.
		location = f"narrative.findings[{finding_index}]"
		# Current finding checked before its citations are followed.
		finding = require_mapping(finding_value, location)
		# Stable key used to keep bundle evidence with its finding.
		finding_id = require_string(finding.get("finding_id"), f"{location}.finding_id")
		if finding_id in bundled_findings:
			raise AuthoringError(f"duplicate finding ID: {finding_id}")

		# Optional pattern identity, defaulting to the finding identity.
		pattern_id_value = finding.get("pattern_id", finding_id)
		# Validated pattern identity carried into the bundle.
		pattern_id = require_string(pattern_id_value, f"{location}.pattern_id")
		# Excerpts retained for this finding after count and character limits.
		excerpts: list[dict[str, object]] = []
		# Characters already retained across this finding's excerpts.
		total_chars = 0
		# Each reference points to evidence cited by this finding.
		for reference in finding_references(finding, location):
			# Evidence entry cited by this finding's current reference.
			entry = indexed_evidence.get(reference)
			if entry is None:
				raise AuthoringError(
					f"{location} contains dangling evidence reference: {reference}"
				)

			# Candidate excerpt, already limited to one entry's character cap.
			text = bounded_excerpt(entry)
			if text is None or len(excerpts) >= MAX_EXCERPTS_PER_FINDING:
				continue

			# Character capacity left for this finding's excerpts.
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

		# The finding's bundle entry; its evidence references list each kept excerpt's
		# reference, so citations dropped by the limits do not appear.
		bundled_findings[finding_id] = {
			"finding_id": finding_id,
			"pattern_id": pattern_id,
			"evidence_references": [excerpt["reference"] for excerpt in excerpts],
			"excerpts": excerpts,
		}

	# Complete bundle with the input digests needed for later validation.
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
	"""Return whether a proposed change quotes its finding's evidence verbatim.

	Args:
		proposed_change: The authored change text to check.
		bundle_finding: The finding's retained evidence excerpts.

	Returns:
		True when the change contains at least MIN_GROUNDING_QUOTE_CHARS
		consecutive characters from one excerpt; otherwise False.
	"""
	if not isinstance(proposed_change, str):
		return False

	# Evidence excerpts available to ground this finding's change.
	excerpts = bundle_finding.get("excerpts")
	if not isinstance(excerpts, list):
		return False

	# Each retained excerpt is a possible source of a grounding quote.
	for excerpt_value in excerpts:
		if not isinstance(excerpt_value, dict):
			continue

		# Verbatim text of the current retained excerpt.
		excerpt_text = excerpt_value.get("text")
		if (
			not isinstance(excerpt_text, str)
			or len(excerpt_text) < MIN_GROUNDING_QUOTE_CHARS
		):
			continue

		# Last excerpt position that can start a full grounding quote.
		last_start = len(excerpt_text) - MIN_GROUNDING_QUOTE_CHARS
		# Candidate start positions are checked for a verbatim match.
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
	"""Require a draft finding to preserve its source and quote its own evidence.

	Args:
		narrative_finding: The narrative's version of the finding, including the
			fields a draft must not change.
		draft_finding: The authored version to validate.
		bundle_finding: The evidence bundle entry for this finding.

	Raises:
		AuthoringError: IDs, fields, or the proposed change fail validation.
	"""
	# Narrative identity that the draft and bundle must preserve.
	finding_id = require_string(
		narrative_finding.get("finding_id"), "narrative finding_id"
	)
	# Finding identity recorded in the evidence bundle.
	bundle_finding_id = require_string(
		bundle_finding.get("finding_id"), "bundle finding_id"
	)
	if bundle_finding_id != finding_id:
		raise AuthoringError("bundle finding_id does not match narrative")

	# Pattern identity that the draft must match.
	pattern_id = require_string(bundle_finding.get("pattern_id"), "bundle pattern_id")
	if draft_finding.get("finding_id") != finding_id:
		raise AuthoringError("draft finding_id does not match narrative")
	if draft_finding.get("pattern_id") != pattern_id:
		raise AuthoringError("draft pattern_id does not match bundle")

	# Original fields plus the metadata permitted in authored drafts.
	allowed_fields = set(narrative_finding) | DRAFT_METADATA_FIELDS
	if set(draft_finding) - allowed_fields:
		raise AuthoringError("draft contains an unexpected finding field")

	# Every original field outside the authored pair must match the narrative.
	for field_name, narrative_value in narrative_finding.items():
		if field_name in AUTHORED_FIELDS:
			continue
		if (
			field_name not in draft_finding
			or draft_finding[field_name] != narrative_value
		):
			raise AuthoringError(f"draft changed immutable field: {field_name}")

	# Both replaceable prose fields must contain non-empty strings.
	for field_name in AUTHORED_FIELDS:
		require_string(draft_finding.get(field_name), f"draft finding.{field_name}")

	# Optional list of quote metadata, checked for string values.
	quotes_used = draft_finding.get("quotes_used")
	# A quotes_used value must be a list in which every entry is a string.
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
	"""Index draft findings by ID and collect repeated IDs.

	Args:
		draft: The authored draft whose findings are inspected.

	Returns:
		Valid finding objects keyed by ID and the IDs that appear more than once.
	"""
	# Draft entries to index when the findings field is an array.
	draft_findings = draft.get("findings")
	if not isinstance(draft_findings, list):
		return {}, set()

	# First valid draft finding encountered for each ID.
	indexed: dict[str, dict[str, object]] = {}
	# IDs that cannot be accepted because they repeat in the draft.
	duplicates: set[str] = set()
	# Only object entries with usable IDs can be indexed.
	for entry_value in draft_findings:
		if not isinstance(entry_value, dict):
			continue

		# Candidate identity of this draft finding.
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
	"""Merge grounded draft prose while retaining narrative text for rejected findings.

	Args:
		narrative: The original findings to preserve and validate.
		draft: The proposed authored findings, or None when unavailable.
		bundle: The finding-specific evidence bundle, or None when unavailable.
		narrative_sha256: The expected narrative digest, computed when omitted.

	Returns:
		A copy of the narrative whose findings carry accepted prose and an
		authored flag, with the narrative digest added.

	Raises:
		AuthoringError: Narrative findings are malformed or repeat an ID.
	"""
	if narrative_sha256 is None:
		# Digest of the canonical narrative JSON when the caller omits one.
		narrative_sha256 = hash_bytes(serialise(narrative).encode("utf-8"))

	# Narrative findings that every output must retain in their original order.
	findings = narrative.get("findings")
	if not isinstance(findings, list) or len(findings) > MAX_FINDINGS:
		raise AuthoringError("narrative.findings must be a bounded array")

	# Validated narrative findings used as the fallback source.
	narrative_findings: list[dict[str, object]] = []
	# IDs already seen while checking for duplicate narrative findings.
	known_finding_ids: set[str] = set()
	# Each index and value identify a narrative finding to retain.
	for index, finding_value in enumerate(findings):
		# Current narrative finding checked before any draft is considered.
		finding = require_mapping(finding_value, f"narrative.findings[{index}]")
		# Stable identity used to align narrative, draft, and bundle entries.
		finding_id = require_string(
			finding.get("finding_id"), f"narrative.findings[{index}].finding_id"
		)
		if finding_id in known_finding_ids:
			raise AuthoringError(f"duplicate narrative finding ID: {finding_id}")
		known_finding_ids.add(finding_id)
		narrative_findings.append(finding)

	# Findings copied from the narrative with accepted prose where available.
	output_findings: list[dict[str, object]] = []
	# Whether missing inputs or mismatched provenance reject all draft prose.
	global_failure = not isinstance(draft, dict) or not isinstance(bundle, dict)
	# Valid draft findings available by identity when provenance matches.
	draft_index: dict[str, dict[str, object]] = {}
	# Draft identities excluded because they occur more than once.
	draft_duplicates: set[str] = set()
	# Bundle findings available by identity when provenance matches.
	bundle_findings: dict[str, object] = {}
	if not global_failure:
		# Digest claimed by the proposed authored draft.
		draft_hash = draft.get("narrative_sha256")
		# Bundle provenance carrying its narrative digest.
		bundle_provenance = bundle.get("provenance")
		# Narrative digest claimed by the bundle, if its provenance is an object.
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
			# Bundle entries checked before per-finding lookup.
			raw_bundle_findings = bundle.get("findings")
			if not isinstance(raw_bundle_findings, dict):
				global_failure = True
			else:
				bundle_findings = raw_bundle_findings

	# Each validated narrative finding is accepted or rejected separately.
	for narrative_finding in narrative_findings:
		# Whether this finding's draft prose passes all checks.
		accepted = False
		# The draft's version of this finding, or None when it has no usable one.
		draft_finding = None
		if not global_failure:
			# Narrative identity used to look up its proposed draft.
			finding_id = narrative_finding["finding_id"]
			if finding_id not in draft_duplicates:
				draft_finding = draft_index.get(finding_id)

		if draft_finding is not None:
			# Evidence entry that must ground this draft finding's change.
			bundle_finding = bundle_findings.get(narrative_finding["finding_id"])
			if isinstance(bundle_finding, dict):
				try:
					validate_authored_finding(
						narrative_finding, draft_finding, bundle_finding
					)
				except AuthoringError:
					# A rejected draft finding keeps the narrative's own prose.
					pass
				else:
					accepted = True

		# Independent copy so accepted prose cannot mutate the source narrative.
		output_finding = deepcopy(narrative_finding)
		if accepted:
			output_finding["consequence"] = draft_finding["consequence"]
			output_finding["exact_change_or_next_investigation"] = draft_finding[
				"exact_change_or_next_investigation"
			]
		output_finding["authored"] = accepted
		output_findings.append(output_finding)

	# Complete narrative copy with validation results and its source digest.
	authored = deepcopy(narrative)
	authored["findings"] = output_findings
	authored["narrative_sha256"] = narrative_sha256
	return authored


def write_json(path: Path, value: dict[str, object]) -> None:
	"""Write one generated JSON artefact, creating its parent directory.

	Args:
		path: The output file to create or replace.
		value: The document to serialise as JSON.
	"""
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(serialise(value), encoding="utf-8")


def fixture_documents() -> tuple[dict[str, object], dict[str, object]]:
	"""Build two findings with isolated evidence for the authoring self-test.

	Returns:
		A narrative with two findings and their separate extraction evidence.
	"""
	# Evidence entries divided evenly between the two fixture rollouts.
	evidence = []
	# Rollout IDs and names keep the two fixture findings separate.
	for rollout_id, finding_name in (("rollout-a", "first"), ("rollout-b", "second")):
		# Index distinguishes the ten evidence references in each rollout.
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

	# Extraction document with one evidence group per rollout.
	extraction = {
		"schema_version": "2.0.0",
		"rollouts": [
			{"rollout_id": "rollout-a", "evidence": evidence[:10]},
			{"rollout_id": "rollout-b", "evidence": evidence[10:]},
		],
	}
	# A narrative whose two findings each cite their own rollout's ten references,
	# numbered by index.
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
	"""Build a draft whose findings quote their own bundle excerpt.

	Args:
		narrative: The original findings to copy into the draft.
		bundle: The matching evidence bundle supplying each quote.
		narrative_sha256: The digest that binds the draft to its narrative.

	Returns:
		A draft that validation accepts for both fixture findings.
	"""
	# Authored fixture findings built from their matching narrative entries.
	draft_findings: list[dict[str, object]] = []
	# Bundle entries used to ground each fixture's proposed change.
	bundle_findings = bundle["findings"]
	# Each narrative finding receives prose grounded in its own bundle entry.
	for narrative_finding in narrative["findings"]:
		# Identity shared by this narrative finding and its bundle entry.
		finding_id = narrative_finding["finding_id"]
		# Evidence bundle entry belonging to this fixture finding.
		bundle_finding = bundle_findings[finding_id]
		# First retained excerpt quoted in the draft's prose.
		quote = bundle_finding["excerpts"][0]["text"]
		# Narrative copy with the permitted authored fields added or replaced.
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
	"""Assert every finding kept its narrative prose and was marked unauthored.

	Args:
		authored: The validation output expected to have fallen back.
		narrative: The original findings used as the fallback source.
	"""
	# Findings returned after a rejected or unavailable draft.
	authored_findings = authored["findings"]
	# Original findings whose prose must remain unchanged.
	narrative_findings = narrative["findings"]
	assert isinstance(authored_findings, list)
	assert len(authored_findings) == len(narrative_findings)
	# Each output finding is compared with its source narrative finding.
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
	"""Check the bundle builder and the draft validation with fixture documents.

	The bundle checks cover repeatable output, each finding keeping only its own
	evidence, and the excerpt limits. The validation checks confirm that grounded
	prose is accepted, and that a finding falls back to the narrative prose when
	the draft has a stale digest, a changed ID, a changed immutable field, a
	mismatched pattern ID, no quote, a quote from another finding, or is missing.
	"""
	# Paired fixture documents with separate evidence for each finding.
	narrative, extraction = fixture_documents()
	# First bounded evidence bundle built from the fixtures.
	bundle = make_authoring_bundle(narrative, extraction, "e" * 64, "n" * 64)
	# Independently built bundle used to check deterministic output.
	repeated_bundle = make_authoring_bundle(narrative, extraction, "e" * 64, "n" * 64)
	assert bundle == repeated_bundle

	# First finding's bundle entry and cited evidence.
	first = bundle["findings"]["finding-first"]
	# Second finding's bundle entry and cited evidence.
	second = bundle["findings"]["finding-second"]
	# References kept for the first finding.
	first_references = set(first["evidence_references"])
	# References kept for the second finding.
	second_references = set(second["evidence_references"])
	assert first_references.isdisjoint(second_references)
	# Every reference kept for the first finding comes from the first rollout.
	assert all(reference.startswith("rollout-a:") for reference in first_references)
	# Every reference kept for the second finding comes from the second rollout.
	assert all(reference.startswith("rollout-b:") for reference in second_references)

	# Each bundled finding must respect the count and character bounds.
	for finding in bundle["findings"].values():
		assert len(finding["excerpts"]) <= MAX_EXCERPTS_PER_FINDING
		# No excerpt is longer than the per-entry character limit.
		assert all(
			len(excerpt["text"]) <= MAX_EXCERPT_CHARS for excerpt in finding["excerpts"]
		)
		# The finding's excerpts together stay within the combined character limit.
		assert (
			sum(len(excerpt["text"]) for excerpt in finding["excerpts"])
			<= MAX_TOTAL_EXCERPT_CHARS
		)
	assert len(serialise(bundle).encode("utf-8")) <= MAX_BUNDLE_BYTES

	# Twenty long excerpts, numbered by index, to test the per-entry and per-finding
	# character limits.
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
	# A narrative whose single finding cites all twenty long excerpts by index.
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
	# Bundle whose retained excerpts reach the character limit.
	long_bundle = make_authoring_bundle(
		long_narrative, long_extraction, "e" * 64, "n" * 64
	)
	# Long fixture finding whose excerpt counts and lengths are checked.
	long_finding = long_bundle["findings"]["finding-long"]
	assert len(long_finding["excerpts"]) == min(
		MAX_EXCERPTS_PER_FINDING,
		MAX_TOTAL_EXCERPT_CHARS // MAX_EXCERPT_CHARS,
	)
	# Each excerpt in the long fixture must reach the per-entry cap.
	assert all(
		len(excerpt["text"]) == MAX_EXCERPT_CHARS
		for excerpt in long_finding["excerpts"]
	)

	# Digest used to bind the validation fixture draft and bundle.
	narrative_sha256 = hash_bytes(serialise(narrative).encode("utf-8"))
	# Evidence bundle carrying the matching narrative digest.
	validation_bundle = make_authoring_bundle(
		narrative, extraction, "e" * 64, narrative_sha256
	)
	# Draft with grounded prose for both fixture findings.
	valid_draft = validation_fixture_draft(
		narrative, validation_bundle, narrative_sha256
	)
	# Validation output expected to accept both drafted findings.
	valid_authored = validate_authored(
		narrative, valid_draft, validation_bundle, narrative_sha256
	)
	assert valid_authored["narrative_sha256"] == narrative_sha256
	# Every finding in the output is marked as authored.
	assert all(finding["authored"] is True for finding in valid_authored["findings"])

	# Draft with stale provenance, forcing fallback for all findings.
	stale_hash_draft = deepcopy(valid_draft)
	stale_hash_draft["narrative_sha256"] = "s" * 64
	assert_fallback_findings(
		validate_authored(
			narrative, stale_hash_draft, validation_bundle, narrative_sha256
		),
		narrative,
	)

	# Draft with one changed finding ID, rejected only for that finding.
	id_mismatch_draft = deepcopy(valid_draft)
	id_mismatch_draft["findings"][0]["finding_id"] = "finding-mismatch"
	# Output used to check that the other finding remains authored.
	id_mismatch_authored = validate_authored(
		narrative, id_mismatch_draft, validation_bundle, narrative_sha256
	)
	assert id_mismatch_authored["findings"][0]["authored"] is False
	assert id_mismatch_authored["findings"][1]["authored"] is True

	# Draft changing a narrative field that authored prose cannot replace.
	immutable_change_draft = deepcopy(valid_draft)
	immutable_change_draft["findings"][0]["owner"] = "tampered-owner"
	# Output used to check local fallback after the immutable-field change.
	immutable_change_authored = validate_authored(
		narrative, immutable_change_draft, validation_bundle, narrative_sha256
	)
	assert immutable_change_authored["findings"][0]["authored"] is False
	assert immutable_change_authored["findings"][1]["authored"] is True

	# Draft with a pattern identity that differs from its evidence bundle.
	pattern_id_mismatch_draft = deepcopy(valid_draft)
	pattern_id_mismatch_draft["findings"][0]["pattern_id"] = "pattern-mismatch"
	# Output used to check local fallback after the pattern mismatch.
	pattern_id_mismatch_authored = validate_authored(
		narrative, pattern_id_mismatch_draft, validation_bundle, narrative_sha256
	)
	assert pattern_id_mismatch_authored["findings"][0]["authored"] is False
	assert pattern_id_mismatch_authored["findings"][1]["authored"] is True

	# Draft whose proposed change omits its retained evidence quote.
	absent_quote_draft = deepcopy(valid_draft)
	absent_quote_draft["findings"][0]["exact_change_or_next_investigation"] = (
		"This proposed change has no retained evidence quote."
	)
	# Output used to check local fallback when the quote is absent.
	absent_quote_authored = validate_authored(
		narrative, absent_quote_draft, validation_bundle, narrative_sha256
	)
	assert absent_quote_authored["findings"][0]["authored"] is False
	assert absent_quote_authored["findings"][1]["authored"] is True

	# Draft whose first change borrows evidence from the second finding.
	cross_finding_quote_draft = deepcopy(valid_draft)
	# Second finding's quote, which cannot ground the first finding.
	cross_finding_quote = validation_bundle["findings"]["finding-second"]["excerpts"][
		0
	]["text"]
	cross_finding_quote_draft["findings"][0]["exact_change_or_next_investigation"] = (
		f"Use this unrelated evidence: {cross_finding_quote}"
	)
	# Output used to check local fallback for a cross-finding quote.
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
	"""Parse input/output paths, validation mode, or the isolated self-test.

	Returns:
		Parsed arguments with incompatible self-test options rejected.
	"""
	# Command-line parser for the bundle, validation, and self-test modes.
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
	# Parsed command-line paths and selected mode.
	arguments = parser.parse_args()
	# Self-test mode refuses any path that differs from its default.
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
	"""Build the authoring bundle, check an authored draft, or run the self-test.

	By default this builds the bundle; --validate checks a draft instead,
	and --selftest runs the built-in checks without reading or writing files.
	Validation writes every narrative finding, using the draft prose only where it
	passes its checks.
	"""
	# Parsed mode and paths chosen by the caller.
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return

	if arguments.validate:
		# Source narrative and exact bytes used to validate draft provenance.
		narrative, narrative_bytes = load_json(arguments.narrative)
		try:
			# Optional bundle used to ground drafted changes.
			bundle, _ = load_json(arguments.bundle_input)
		except AuthoringError:
			bundle = None
		try:
			# Optional authored draft to validate against the narrative.
			draft, _ = load_json(arguments.draft)
		except AuthoringError:
			draft = None
		# Narrative output with accepted prose or deterministic fallbacks.
		authored = validate_authored(
			narrative,
			draft,
			bundle,
			hash_bytes(narrative_bytes),
		)
		write_json(arguments.authored_output, authored)
		print(f"Wrote authored findings for {len(authored['findings'])} findings")
		return

	# Source extraction and exact bytes bound into the evidence bundle.
	extraction, extraction_bytes = load_json(arguments.input)
	# Source narrative and exact bytes bound into the evidence bundle.
	narrative, narrative_bytes = load_json(arguments.narrative)
	# Finding-specific evidence bundle written for the authoring step.
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

#!/usr/bin/env python3
"""Validate the bound Codex insights provenance chain and render the actionable HTML report."""

from __future__ import annotations

import argparse
import copy
import datetime
import html
import os
import sys
import tempfile
from pathlib import Path

import codex_insights_author as author
import codex_insights_facets as facets

# The Codex data folder, taken from CODEX_HOME when it is set.
CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
# The directory holding the inputs and generated HTML reports.
USAGE_DATA_DIRECTORY = CODEX_HOME / "usage-data"
# The default extraction document read for a report.
DEFAULT_EXTRACTION_PATH = USAGE_DATA_DIRECTORY / "latest.json"
# The default conversation facets document read for a report.
DEFAULT_FACETS_PATH = USAGE_DATA_DIRECTORY / "latest-facets.json"
# The default narrative document read for a report.
DEFAULT_NARRATIVE_PATH = USAGE_DATA_DIRECTORY / "latest-narrative.json"
# The default file containing reviewed prose for narrative findings.
DEFAULT_AUTHORED_PATH = USAGE_DATA_DIRECTORY / "latest-authored.json"
# The timezone used for report filenames.
UTC = datetime.timezone.utc

# The reader-facing names for finding kinds.
KIND_LABELS = {
	"tool_failure": "Tool failure",
	"verification_gap": "Verification gap",
	"correction": "User correction",
	"configuration_touch": "Configuration touch",
	"successful_behaviour": "Successful behaviour",
	"approach_change": "Approach change",
	"retry": "Retry",
	"interruption": "Interruption",
	"rollback": "Rollback",
}
# The report sections and the finding kinds shown in each one.
KIND_GROUPS = (
	("failures", "Repeated failures", frozenset({"tool_failure", "verification_gap"})),
	("corrections", "Repeated user corrections", frozenset({"correction"})),
	(
		"configuration",
		"Configuration opportunities",
		frozenset({"configuration_touch"}),
	),
	(
		"successes",
		"Successful behaviours worth standardising",
		frozenset({"successful_behaviour"}),
	),
	(
		"workflow",
		"Workflow patterns",
		frozenset({"approach_change", "retry", "interruption", "rollback"}),
	),
)
# The reader-facing explanations of configuration lookup results.
CONFIGURATION_STATUS_LABELS = {
	"missing": "Missing — no matching guidance found",
	"already_remediated": "Already remediated — guidance already covers this",
	"present_but_ignored": "Present but ignored — guidance exists but was not followed",
	"ambiguous": "Ambiguous — could not resolve to one configuration surface",
	"unavailable": "Unavailable — the surface could not be read",
	"not_applicable": "Not tied to a named configuration surface",
}

# The CSS included in each standalone HTML report.
REPORT_STYLE = """
:root {
  color-scheme: light;
  --background: #f8fafc;
  --surface: #ffffff;
  --text: #1f2937;
  --heading: #111827;
  --muted: #4b5563;
  --border: #6b7280;
  --accent: #005a9c;
  --focus: #005fcc;
  --highlight: #eff6ff;
  --high-confidence: #0f5132;
  --low-confidence: #664d03;
}

* {
  box-sizing: border-box;
}

html {
  background: var(--background);
}

body {
  margin: 0;
  color: var(--text);
  background: var(--background);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 1rem;
  line-height: 1.5;
}

a {
  color: var(--accent);
}

a:focus-visible,
main:focus-visible {
  outline: 3px solid var(--focus);
  outline-offset: 3px;
}

.skip-link {
  position: absolute;
  top: 0.75rem;
  left: 0.75rem;
  z-index: 1;
  padding: 0.65rem 0.9rem;
  color: var(--heading);
  background: var(--surface);
  border: 2px solid var(--focus);
  transform: translateY(-200%);
}

.skip-link:focus {
  transform: translateY(0);
}

.page-width {
  width: min(100%, 72rem);
  margin: 0 auto;
  padding: 0 clamp(1rem, 4vw, 3rem);
}

.report-header {
  padding: clamp(2rem, 6vw, 4rem) 0 2rem;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
}

h1,
h2,
h3,
h4 {
  color: var(--heading);
  line-height: 1.2;
  overflow-wrap: anywhere;
}

h1 {
  max-width: 24ch;
  margin: 0;
  font-size: clamp(2rem, 5vw, 3rem);
}

h2 {
  margin: 0;
  font-size: clamp(1.5rem, 3vw, 2rem);
}

h3 {
  margin: 0;
  font-size: 1.2rem;
}

h4 {
  margin: 1.25rem 0 0.35rem;
  font-size: 1rem;
}

p {
  max-width: 65ch;
  overflow-wrap: anywhere;
}

.metadata {
  margin: 1rem 0 0;
  color: var(--muted);
}

.section-nav {
  padding: 1.5rem 0;
  background: var(--highlight);
  border-bottom: 1px solid var(--border);
}

.section-nav ol {
  display: grid;
  gap: 0.5rem 1.5rem;
  margin: 0;
  padding-left: 1.5rem;
}

.report-main {
  padding-top: 2rem;
  padding-bottom: 3rem;
}

.report-section {
  min-width: 0;
  margin: 0 0 2rem;
  padding: clamp(1rem, 3vw, 2rem);
  background: var(--surface);
  border: 1px solid var(--border);
}

.report-section:last-child {
  margin-bottom: 0;
}

.section-summary {
  margin: 0.75rem 0 1.5rem;
}

.findings,
.lead-list,
.evidence-list,
.limitations-list {
  margin: 0;
  padding-left: 1.5rem;
}

.finding {
  min-width: 0;
  margin-top: 1.75rem;
  padding-top: 1.75rem;
  border-top: 1px solid var(--border);
}

.finding:first-child {
  margin-top: 0;
  padding-top: 0;
  border-top: none;
}

.finding-meta {
  margin: 0.5rem 0;
}

.authorship-status {
  margin: 0.5rem 0;
  color: var(--muted);
  font-size: 0.9rem;
}

.badge {
  display: inline-block;
  margin: 0.15rem 0.35rem 0.15rem 0;
  padding: 0.15rem 0.55rem;
  color: var(--heading);
  font-size: 0.85rem;
  background: var(--highlight);
  border: 1px solid var(--border);
  border-radius: 999px;
}

.badge-confidence-high {
  color: var(--high-confidence);
  border-color: var(--high-confidence);
}

.badge-confidence-low {
  color: var(--low-confidence);
  border-color: var(--low-confidence);
}

.proposed-change,
.current-state,
.evidence,
.limitations {
  min-width: 0;
  margin-top: 1rem;
  padding: 0.9rem 1rem;
  background: var(--highlight);
  border-left: 0.3rem solid var(--accent);
}

.proposed-change h4,
.current-state h4,
.evidence h4,
.limitations h4 {
  margin-top: 0;
}

.evidence-list li,
.limitations-list li {
  margin-top: 0.55rem;
  overflow-wrap: anywhere;
}

.evidence-list li:first-child,
.limitations-list li:first-child {
  margin-top: 0;
}

code {
  overflow-wrap: anywhere;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.95em;
}

.evidence-detail {
  display: block;
}

.empty {
  margin-bottom: 0;
  color: var(--muted);
  font-style: italic;
}

.appendix-table {
  width: 100%;
  border-collapse: collapse;
}

.appendix-table th,
.appendix-table td {
  padding: 0.4rem 0.6rem;
  text-align: left;
  border-bottom: 1px solid var(--border);
}

.report-footer {
  padding: 1.5rem 0 3rem;
  color: var(--muted);
}

@media (min-width: 50rem) {
  .section-nav ol {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (prefers-reduced-motion: reduce) {
  html {
    scroll-behavior: auto;
  }
}
""".strip()


def load_and_validate(
	extraction_path: Path, facets_path: Path, narrative_path: Path
) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
	"""Load the report inputs after checking their provenance chain.

	Args:
		extraction_path: The extraction JSON file used to build the report.
		facets_path: The facets JSON file derived from that extraction.
		narrative_path: The narrative JSON file derived from those facets.

	Returns:
		The validated extraction information, facets document, and narrative document.

	Raises:
		facets.ProvenanceError: An input cannot be read, is malformed, or does not match the inputs before it.
	"""
	# The extraction metadata and rollout index used to check later documents.
	extraction_info = facets.validate_extraction(extraction_path)
	# The facets document whose source must match the extraction.
	facets_document = facets.load_json(facets_path)
	facets.validate_facets(facets_document, extraction_info)
	# The hash of the facets file, which the narrative must record.
	facets_sha256 = facets.hash_bytes(facets_path.read_bytes())
	# The narrative document whose provenance must match both earlier inputs.
	narrative_document = facets.load_json(narrative_path)
	facets.validate_narrative(
		narrative_document, extraction_info, facets_document, facets_sha256
	)
	return extraction_info, facets_document, narrative_document


def validate_authored_document(
	narrative_document: dict[str, object],
	authored_document: dict[str, object],
	narrative_sha256: str | None = None,
) -> None:
	"""Reject authored findings that change the narrative beyond approved prose.

	Args:
		narrative_document: The original narrative and its finding IDs.
		authored_document: The proposed prose and authorship markers for those findings.
		narrative_sha256: The expected hash of the narrative file, or None to skip the hash check.

	Raises:
		facets.ProvenanceError: The files disagree or an authored finding is invalid.
	"""
	if (
		narrative_sha256 is not None
		and authored_document.get("narrative_sha256") != narrative_sha256
	):
		raise facets.ProvenanceError(
			"authored narrative SHA-256 does not match latest-narrative.json"
		)

	# The original findings, each of which needs exactly one authored entry.
	narrative_findings = narrative_document.get("findings")
	# The candidate entries checked against the original findings.
	authored_findings = authored_document.get("findings")
	if not isinstance(narrative_findings, list):
		raise facets.ProvenanceError("narrative.findings must be an array")
	if not isinstance(authored_findings, list) or len(authored_findings) != len(
		narrative_findings
	):
		raise facets.ProvenanceError(
			"authored.findings must cover every narrative finding"
		)

	# The original findings indexed by ID for order-independent comparison.
	narrative_index: dict[str, dict[str, object]] = {}
	# Each original entry and its position for validation errors.
	for index, finding_value in enumerate(narrative_findings):
		# The validated original finding at this position.
		finding = facets.require_mapping(finding_value, f"narrative.findings[{index}]")
		# The identifier used to match this finding with authored prose.
		finding_id = facets.require_string(
			finding.get("finding_id"), "narrative finding_id"
		)
		if finding_id in narrative_index:
			raise facets.ProvenanceError(
				f"duplicate narrative finding ID: {finding_id}"
			)
		narrative_index[finding_id] = finding

	# Authored finding IDs already checked, so duplicates can be rejected.
	seen_ids: set[str] = set()
	# Each authored entry and its position for validation errors.
	for index, authored_value in enumerate(authored_findings):
		# The validated authored finding at this position.
		authored_finding = facets.require_mapping(
			authored_value, f"authored.findings[{index}]"
		)
		# The ID that must match a narrative finding and appear only once in the authored file.
		finding_id = facets.require_string(
			authored_finding.get("finding_id"), "authored finding_id"
		)
		if finding_id in seen_ids:
			raise facets.ProvenanceError(f"duplicate authored finding ID: {finding_id}")
		seen_ids.add(finding_id)
		# The original entry whose non-prose fields must stay unchanged.
		narrative_finding = narrative_index.get(finding_id)
		if narrative_finding is None:
			raise facets.ProvenanceError(
				f"authored finding ID is not in the narrative: {finding_id}"
			)
		if authored_finding.get("authored") not in (True, False):
			raise facets.ProvenanceError(
				f"authored finding marker is invalid: {finding_id}"
			)

		# The original fields plus the authorship marker allowed in this entry.
		allowed_fields = set(narrative_finding) | {"authored"}
		if set(authored_finding) - allowed_fields:
			raise facets.ProvenanceError(
				f"authored finding has unexpected fields: {finding_id}"
			)
		# Each original field and value to compare against the authored entry.
		for field_name, narrative_value in narrative_finding.items():
			if field_name in author.AUTHORED_FIELDS:
				continue
			if authored_finding.get(field_name) != narrative_value:
				raise facets.ProvenanceError(
					f"authored finding changed immutable field: {field_name}"
				)
		# Each prose field that must remain a string.
		for field_name in author.AUTHORED_FIELDS:
			facets.require_string(
				authored_finding.get(field_name), f"authored finding.{field_name}"
			)

	if seen_ids != set(narrative_index):
		raise facets.ProvenanceError(
			"authored findings do not match narrative finding IDs"
		)


def load_authored(
	authored_path: Path,
	narrative_path: Path,
	narrative_document: dict[str, object],
) -> dict[str, object]:
	"""Load authored findings bound to the current narrative file.

	Args:
		authored_path: The file containing authored finding prose.
		narrative_path: The narrative file whose SHA-256 hash the authored file must record.
		narrative_document: The validated narrative used for finding comparison.

	Returns:
		The authored document after its hash and findings pass validation.

	Raises:
		facets.ProvenanceError: A file cannot be read or the authored findings do not match the narrative.
	"""
	try:
		# The authored document; the raw file bytes returned with it are not needed.
		authored_document, _ = author.load_json(authored_path)
		# The current narrative hash required by the authored file.
		narrative_sha256 = facets.hash_bytes(narrative_path.read_bytes())
	except author.AuthoringError as error:
		raise facets.ProvenanceError(
			f"cannot load authored findings: {error}"
		) from error
	except OSError as error:
		raise facets.ProvenanceError(
			f"cannot read narrative artefact {narrative_path}: {error}"
		) from error

	validate_authored_document(narrative_document, authored_document, narrative_sha256)
	return authored_document


def apply_authored_findings(
	narrative_document: dict[str, object], authored_document: dict[str, object] | None
) -> dict[str, object]:
	"""Copy the narrative and replace prose only for accepted authored findings.

	Args:
		narrative_document: The validated source findings and their default prose.
		authored_document: Accepted replacement prose, or None to keep all defaults.

	Returns:
		A copy of the narrative with accepted prose applied and each finding's
		authored marker set to show whether its prose was replaced.

	Raises:
		facets.ProvenanceError: The authored findings do not match the narrative.
	"""
	# A separate document so rendering does not change the caller's narrative.
	merged_document = copy.deepcopy(narrative_document)
	# The copied findings whose prose may be replaced.
	narrative_findings = merged_document.get("findings", [])
	if not isinstance(narrative_findings, list):
		return merged_document

	if authored_document is None:
		# No replacements when an authored document was not supplied.
		authored_index: dict[str, dict[str, object]] = {}
	else:
		validate_authored_document(narrative_document, authored_document)
		# Each authored finding that has a string ID, keyed by that ID.
		authored_index = {
			finding["finding_id"]: finding
			for finding in authored_document.get("findings", [])
			if isinstance(finding, dict) and isinstance(finding.get("finding_id"), str)
		}

	# Each copied finding that may receive accepted prose.
	for finding in narrative_findings:
		if not isinstance(finding, dict):
			continue
		finding["authored"] = False
		# The authored entry with the same ID, if there is one.
		authored_finding = authored_index.get(finding.get("finding_id"))
		if authored_finding is None or authored_finding.get("authored") is not True:
			continue
		finding["consequence"] = authored_finding["consequence"]
		finding["exact_change_or_next_investigation"] = authored_finding[
			"exact_change_or_next_investigation"
		]
		finding["authored"] = True

	return merged_document


def escaped(value: object) -> str:
	"""Escape dynamic text for an HTML text node or attribute.

	Args:
		value: The value to display without interpreting it as HTML.

	Returns:
		The escaped string, including escaped quotation marks.
	"""
	return html.escape(str(value), quote=True)


def display_optional(value: object) -> str:
	"""Display a missing optional value with an explicit placeholder.

	Args:
		value: The optional value to display.

	Returns:
		Escaped text, or "Not available" for None or an empty string.
	"""
	return "Not available" if value in (None, "") else escaped(value)


def finding_sort_key(finding: dict[str, object]) -> tuple[int, int, int]:
	"""Rank findings by confidence, occurrence, and conversation spread.

	Args:
		finding: The validated finding with confidence and frequency counts.

	Returns:
		A sortable tuple placing high confidence and larger counts first.
	"""
	# The counts used to order findings within a confidence group.
	frequency = finding["frequency"]
	return (
		0 if finding["confidence"] == "high" else 1,
		-int(frequency["occurrences"]),
		-int(frequency["unique_conversations"]),
	)


def render_lead_list(findings: list[dict[str, object]]) -> list[str]:
	"""Build the ranked list of proposed changes at the top of the report.

	Args:
		findings: The validated findings to link to their report sections.

	Returns:
		HTML lines for the ordered list or its empty state.
	"""
	if not findings:
		return [
			'<p class="empty">No repeated pattern reached the two-conversation recurrence bar in this window.</p>'
		]

	# The ordered list of links and proposed changes.
	lines = ['<ol class="lead-list">']
	# Each finding in the order readers see in the summary.
	for finding in sorted(findings, key=finding_sort_key):
		# The readable kind shown before the proposed target.
		kind_label = KIND_LABELS.get(finding["kind"], finding["kind"])
		lines.append(
			"<li>"
			f'<a href="#finding-{escaped(finding["finding_id"])}">'
			f"{escaped(kind_label)}: {escaped(finding['proposed_target'])}"
			"</a> — "
			f"{escaped(finding['exact_change_or_next_investigation'])}"
			"</li>"
		)
	lines.append("</ol>")
	return lines


def render_current_state(current_configuration_status: dict[str, object]) -> list[str]:
	"""Show the checked configuration state for one finding.

	Args:
		current_configuration_status: The status and any checked surfaces.

	Returns:
		HTML lines describing the status and each checked surface.
	"""
	# The overall result of checking the named configuration surfaces.
	status = current_configuration_status.get("status")
	# The HTML block that introduces the result.
	lines = [
		'<div class="current-state">',
		"<h4>Current configuration state</h4>",
		f"<p>{escaped(CONFIGURATION_STATUS_LABELS.get(status, status))}</p>",
	]
	# The individual configuration surfaces checked for this finding.
	surfaces = current_configuration_status.get("surfaces") or []
	if surfaces:
		lines.append('<ul class="evidence-list">')
		# Each named surface and its specific lookup result.
		for surface in surfaces:
			# The displayed file path or surface name when no path is available.
			path = display_optional(surface.get("path") or surface.get("surface"))
			# The readable explanation of this surface's status.
			surface_status = escaped(
				CONFIGURATION_STATUS_LABELS.get(
					surface.get("status"), surface.get("status")
				)
			)
			lines.append(f"<li><code>{path}</code>: {surface_status}</li>")
		lines.append("</ul>")
	lines.append("</div>")
	return lines


def render_evidence(citations: list[dict[str, object]]) -> list[str]:
	"""Build the source-ordered evidence list for one finding.

	Args:
		citations: The retained conversation excerpts and their source details.

	Returns:
		HTML lines with each citation's conversation, time, and detail.
	"""
	# The HTML block holding the citation list.
	lines = [
		'<div class="evidence">',
		"<h4>Supporting evidence</h4>",
		'<ul class="evidence-list">',
	]
	# Each retained citation to display in source order.
	for citation in citations:
		# The conversation identifier, or an explicit missing-value label.
		conversation_id = display_optional(citation.get("conversation_id"))
		# The recorded citation time when one is available.
		timestamp = citation.get("timestamp")
		# The time element or a label for a missing time.
		time_html = (
			f'<time datetime="{escaped(timestamp)}">{escaped(timestamp)}</time>'
			if timestamp
			else "<span>time unavailable</span>"
		)
		lines.append(
			"<li>"
			f"<code>{conversation_id}</code> {time_html}"
			'<span class="evidence-detail">'
			f"{escaped(citation.get('detail') or 'No excerpt retained')}"
			"</span>"
			"</li>"
		)
	lines.extend(["</ul>", "</div>"])
	return lines


def render_limitations(limitations: list[str]) -> list[str]:
	"""Show the counterevidence and limits attached to one finding.

	Args:
		limitations: The finding's recorded caveats and contrary evidence.

	Returns:
		HTML lines for the list of limitations.
	"""
	# The HTML block holding the limitation list.
	lines = [
		'<div class="limitations">',
		"<h4>Limitations</h4>",
		'<ul class="limitations-list">',
	]
	# Each limitation shown as one list item.
	for limitation in limitations:
		lines.append(f"<li>{escaped(limitation)}</li>")
	lines.extend(["</ul>", "</div>"])
	return lines


def render_finding(finding: dict[str, object]) -> list[str]:
	"""Build one finding's evidence, current state, and proposed change.

	Args:
		finding: The validated finding to display.

	Returns:
		HTML lines for the finding and its supporting sections.
	"""
	# The readable label for this finding's kind.
	kind_label = KIND_LABELS.get(finding["kind"], finding["kind"])
	# The occurrence and conversation counts shown in badges.
	frequency = finding["frequency"]
	# The earliest and latest source times shown in the metadata.
	time_span = finding["time_span"]
	# The confidence level used for the visible label and CSS class.
	confidence = finding["confidence"]
	# The visible note distinguishing accepted prose from default text.
	authorship_status = (
		"Agent-authored prose (unverified)"
		if finding.get("authored") is True
		else "Not agent-authored: deterministic fallback"
	)
	# The opening HTML and summary of the finding.
	lines = [
		f'<li class="finding" id="finding-{escaped(finding["finding_id"])}">',
		f"<h3>{escaped(kind_label)}: {escaped(finding['observed_pattern'])}</h3>",
		'<p class="finding-meta">',
		f'<span class="badge badge-confidence-{escaped(confidence)}">Confidence: {escaped(confidence)}</span>',
		f'<span class="badge">{escaped(frequency["occurrences"])} occurrences '
		f"across {escaped(frequency['unique_conversations'])} conversations</span>",
		f'<span class="badge">{display_optional(time_span.get("since"))} '
		f"to {display_optional(time_span.get('until'))}</span>",
		"</p>",
		f'<p class="authorship-status"><strong>Prose status:</strong> {escaped(authorship_status)}</p>',
		f"<p><strong>Consequence:</strong> {escaped(finding['consequence'])}</p>",
		'<div class="proposed-change">',
		"<h4>Proposed change</h4>",
		f"<p><strong>Owner:</strong> {escaped(finding['owner'])}. "
		f"<strong>Layer:</strong> {escaped(finding['proposed_layer'])}. "
		f"<strong>Target:</strong> {escaped(finding['proposed_target'])}.</p>",
		f"<p>{escaped(finding['exact_change_or_next_investigation'])}</p>",
		"</div>",
	]
	lines.extend(render_current_state(finding["current_configuration_status"]))
	lines.extend(render_evidence(finding["supporting_evidence"]))
	lines.extend(render_limitations(finding["counterevidence_or_limitations"]))
	lines.append("</li>")
	return lines


def render_category_section(
	section_id: str, title: str, findings: list[dict[str, object]]
) -> list[str]:
	"""Build a finding section with an explicit empty state when needed.

	Args:
		section_id: The anchor shared by the section and its navigation link.
		title: The heading shown for this group of findings.
		findings: The findings assigned to the group.

	Returns:
		HTML lines for the section and its ordered findings.
	"""
	# The opening section and its labelled heading.
	lines = [
		f'<section id="{section_id}" class="report-section" aria-labelledby="{section_id}-title">',
		f'<h2 id="{section_id}-title">{escaped(title)}</h2>',
	]
	if findings:
		lines.append('<ul class="findings">')
		# Each finding in the order shown within this section.
		for finding in sorted(findings, key=finding_sort_key):
			lines.extend(render_finding(finding))
		lines.append("</ul>")
	else:
		lines.append(
			f'<p class="empty">No evidenced {escaped(title.lower())} were found in this window.</p>'
		)
	lines.append("</section>")
	return lines


def render_evidence_limits_section(
	section_id: str,
	facets_document: dict[str, object],
	narrative_document: dict[str, object],
) -> list[str]:
	"""Show distinct evidence limits from the facets and narrative.

	Args:
		section_id: The anchor for this report section.
		facets_document: The facets and their source limitations.
		narrative_document: The narrative and its additional limitations.

	Returns:
		HTML lines for the combined limits or an empty state.
	"""
	# The facets and narrative limits without duplicates, in first-seen order.
	limitations = list(
		dict.fromkeys(
			facets_document.get("limitations", [])
			+ narrative_document.get("limitations", [])
		)
	)
	# Pattern totals used to explain why single observations are omitted.
	counts = facets_document.get("counts", {})
	# The number of patterns that did not repeat, which the report leaves out.
	illustrated_only = counts.get("pattern_count", 0) - counts.get(
		"repeated_pattern_count", 0
	)
	if illustrated_only:
		limitations.append(
			f"{illustrated_only} pattern(s) were observed once and are not shown; "
			"a repeated pattern needs at least two unique conversations."
		)
	# The opening section and its evidence-limit heading.
	lines = [
		f'<section id="{section_id}" class="report-section" aria-labelledby="{section_id}-title">',
		f'<h2 id="{section_id}-title">Evidence limits</h2>',
	]
	if limitations:
		lines.append('<ul class="limitations-list">')
		# Each distinct limit shown as one list item.
		for limitation in limitations:
			lines.append(f"<li>{escaped(limitation)}</li>")
		lines.append("</ul>")
	else:
		lines.append(
			'<p class="empty">No evidence limits were recorded for this window.</p>'
		)
	lines.append("</section>")
	return lines


def render_appendix_section(
	section_id: str,
	extraction_info: dict[str, object],
	facets_document: dict[str, object],
) -> list[str]:
	"""Show source totals and extraction provenance in the appendix.

	Args:
		section_id: The anchor for the appendix section.
		extraction_info: The validated extraction document, rollout index, and hash binding.
		facets_document: The validated facets and pattern counts.

	Returns:
		HTML lines for the appendix table.
	"""
	# Totals recorded by the source extraction.
	extraction_counts = extraction_info["document"].get("counts", {})
	# Totals recorded after conversation facets were built.
	facets_counts = facets_document.get("counts", {})
	# The distinct project paths recorded across the extracted rollouts.
	project_paths = {
		rollout.get("project_path")
		for rollout in extraction_info["rollout_index"].values()
		if rollout.get("project_path")
	}
	# The extraction schema and hash bound to the report inputs.
	binding = extraction_info["binding"]
	# The labels and values presented in the appendix table.
	rows = [
		("Repository directories touched", str(len(project_paths))),
		("Rollouts extracted", str(extraction_counts.get("rollout_count", 0))),
		("Conversations", str(extraction_counts.get("conversation_count", 0))),
		("Subagent rollouts", str(extraction_counts.get("subagent_rollout_count", 0))),
		(
			"Conversation facets classified",
			str(facets_counts.get("conversation_facet_count", 0)),
		),
		("Patterns observed", str(facets_counts.get("pattern_count", 0))),
		(
			"Repeated patterns promoted to findings",
			str(facets_counts.get("repeated_pattern_count", 0)),
		),
		("Extraction schema", str(binding.get("extraction_schema_version"))),
		("Extraction SHA-256", str(binding.get("extraction_sha256"))),
	]
	# The opening section and table markup.
	lines = [
		f'<section id="{section_id}" class="report-section" aria-labelledby="{section_id}-title">',
		f'<h2 id="{section_id}-title">Appendix: totals and provenance</h2>',
		'<table class="appendix-table">',
		"<tbody>",
	]
	# Each appendix label and value displayed as one table row.
	for label, value in rows:
		lines.append(
			f'<tr><th scope="row">{escaped(label)}</th><td>{escaped(value)}</td></tr>'
		)
	lines.extend(["</tbody>", "</table>", "</section>"])
	return lines


def render_report(
	narrative_document: dict[str, object],
	facets_document: dict[str, object],
	extraction_info: dict[str, object],
	authored_document: dict[str, object] | None = None,
) -> str:
	"""Build a standalone HTML report from validated source documents.

	Args:
		narrative_document: The validated narrative and its findings.
		facets_document: The validated facets, evidence limits, and pattern counts.
		extraction_info: The validated extraction document, rollout index, hash
			binding, and file path.
		authored_document: Accepted authored prose, or None for default wording.

	Returns:
		The complete HTML page with navigation, findings, and provenance.
	"""
	# A copy with approved authored prose applied where available.
	display_document = apply_authored_findings(narrative_document, authored_document)
	# The findings used in the summary and category sections.
	findings = display_document.get("findings", [])
	# The source time window displayed in the report header.
	window = narrative_document["provenance"]["window"]

	# The section IDs, titles, and rendered content used by navigation and the page.
	sections: list[tuple[str, str, list[str]]] = []
	# Each finding section's ID, title, and the finding kinds it shows.
	for group_id, title, kinds in KIND_GROUPS:
		# The findings whose kinds belong in this section.
		group_findings = [finding for finding in findings if finding["kind"] in kinds]
		sections.append(
			(group_id, title, render_category_section(group_id, title, group_findings))
		)
	sections.append(
		(
			"evidence-limits",
			"Evidence limits",
			render_evidence_limits_section(
				"evidence-limits", facets_document, narrative_document
			),
		)
	)
	sections.append(
		(
			"appendix",
			"Appendix: totals and provenance",
			render_appendix_section("appendix", extraction_info, facets_document),
		)
	)

	# The document opening, title, navigation, and report metadata.
	lines = [
		"<!doctype html>",
		'<html lang="en">',
		"<head>",
		'<meta charset="utf-8">',
		'<meta name="viewport" content="width=device-width, initial-scale=1">',
		"<title>Codex insights report</title>",
		"<style>",
		REPORT_STYLE,
		"</style>",
		"</head>",
		"<body>",
		'<a class="skip-link" href="#main">Skip to report</a>',
		'<header class="report-header">',
		'<div class="page-width">',
		"<h1>Codex insights report</h1>",
		'<p class="metadata">',
		f"Generated {escaped(narrative_document['generated_at'])}. "
		f"Window: {display_optional(window.get('since'))} to {display_optional(window.get('until'))}.",
		"</p>",
		"</div>",
		"</header>",
		'<nav class="section-nav" aria-label="Report sections">',
		'<div class="page-width">',
		"<ol>",
		'<li><a href="#proposed-changes">Proposed changes</a></li>',
	]
	# Each section's navigation target and visible title.
	for section_id, title, _ in sections:
		lines.append(f'<li><a href="#{section_id}">{escaped(title)}</a></li>')
	lines.extend(["</ol>", "</div>", "</nav>"])
	lines.append('<main id="main" class="report-main page-width" tabindex="-1">')
	lines.extend(
		[
			'<section id="proposed-changes" class="report-section" aria-labelledby="proposed-changes-title">',
			'<h2 id="proposed-changes-title">Proposed changes</h2>',
			'<p class="section-summary">Ranked by confidence, then by how often the pattern recurred.</p>',
		]
	)
	lines.extend(render_lead_list(findings))
	lines.append("</section>")
	# The rendered content for each report section.
	for _, _, section_lines in sections:
		lines.extend(section_lines)
	lines.extend(
		[
			"</main>",
			'<footer class="report-footer">',
			'<div class="page-width">',
			f"<p>Source extraction: <code>{escaped(extraction_info['path'])}</code>.</p>",
			"</div>",
			"</footer>",
			"</body>",
			"</html>",
		]
	)
	return "\n".join(lines) + "\n"


def report_path(now: datetime.datetime | None = None) -> Path:
	"""Choose a UTC-timestamped report path in Codex usage data.

	Args:
		now: The time to use, or None to read the current time.

	Returns:
		The path for an HTML report at that UTC timestamp.
	"""
	# The supplied or current time from which the filename is made.
	now = datetime.datetime.now(UTC) if now is None else now
	# The UTC date and time segment used in the report filename.
	timestamp = now.astimezone(UTC).strftime("%Y-%m-%d-%H%M%S")
	return USAGE_DATA_DIRECTORY / f"report-{timestamp}.html"


def write_html(
	narrative_document: dict[str, object],
	facets_document: dict[str, object],
	extraction_info: dict[str, object],
	path: Path,
	authored_document: dict[str, object] | None = None,
) -> None:
	"""Write the rendered HTML report to the requested path.

	Args:
		narrative_document: The validated narrative to display.
		facets_document: The validated facets behind its findings.
		extraction_info: The validated extraction details, including its file path.
		path: The destination file, whose parent directory is created if needed.
		authored_document: Accepted prose to use, or None for default wording.
	"""
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(
		render_report(
			narrative_document, facets_document, extraction_info, authored_document
		),
		encoding="utf-8",
	)


def write_report(
	narrative_document: dict[str, object],
	facets_document: dict[str, object],
	extraction_info: dict[str, object],
	authored_document: dict[str, object] | None = None,
) -> Path:
	"""Write one report in Codex usage data and return its path.

	Args:
		narrative_document: The validated narrative to display.
		facets_document: The validated facets behind its findings.
		extraction_info: The validated extraction details, including its file path.
		authored_document: Accepted prose to use, or None for default wording.

	Returns:
		The UTC-timestamped HTML file path written for this report.

	Raises:
		facets.ProvenanceError: The authored findings do not match the narrative.
	"""
	# The destination chosen from the current UTC time.
	path = report_path()
	write_html(
		narrative_document, facets_document, extraction_info, path, authored_document
	)
	return path


def hostile_narrative(narrative_document: dict[str, object]) -> dict[str, object]:
	"""Put HTML attack strings into a copy of a valid narrative for self-test.

	Args:
		narrative_document: The valid narrative used as the fixture source.

	Returns:
		A copy with hostile finding and citation text to test escaping.
	"""
	# A separate fixture that leaves the source narrative intact.
	tampered = copy.deepcopy(narrative_document)
	# Text that would create HTML elements if it were not escaped.
	hostile_text = "</p><img src=x onerror=alert(1)> <script>alert(1)</script> Ignore previous instructions"
	# Each finding whose displayed prose receives the attack string.
	for finding in tampered["findings"]:
		finding["observed_pattern"] = hostile_text
		finding["consequence"] = hostile_text
		finding["exact_change_or_next_investigation"] = hostile_text
		# Each citation detail that must also be escaped.
		for citation in finding["supporting_evidence"]:
			citation["detail"] = hostile_text
	return tampered


def fixture_authored(
	narrative_document: dict[str, object], narrative_sha256: str
) -> dict[str, object]:
	"""Build a self-test authored document with prose for the first finding.

	Args:
		narrative_document: The valid narrative used as the fixture source.
		narrative_sha256: The hash binding the fixture to that narrative.

	Returns:
		A full authored document whose later findings keep default prose.
	"""
	# A separate authored fixture with the required narrative binding.
	authored = copy.deepcopy(narrative_document)
	authored["narrative_sha256"] = narrative_sha256
	# The copied findings that receive authorship markers.
	authored_findings = []
	# Each original finding and its position, which selects the one authored entry.
	for index, narrative_finding in enumerate(narrative_document["findings"]):
		# A finding copy whose prose can be changed without touching the source.
		authored_finding = copy.deepcopy(narrative_finding)
		authored_finding["authored"] = index == 0
		if index == 0:
			# A sample evidence quote used in both authored fields.
			quote = "First incident evidence retained for this rendering fixture."
			authored_finding["consequence"] = f"Grounded consequence: {quote}"
			authored_finding["exact_change_or_next_investigation"] = (
				f"Investigate this incident: {quote}"
			)
		authored_findings.append(authored_finding)
	authored["findings"] = authored_findings
	return authored


def expect_provenance_error(callback: object) -> None:
	"""Check that a self-test action rejects invalid provenance.

	Args:
		callback: The action expected to raise ProvenanceError.
	"""
	try:
		callback()
	except facets.ProvenanceError:
		return

	raise AssertionError("expected ProvenanceError")


def run_selftest() -> None:
	"""Run the self-test against sample files in a temporary folder.

	The checks cover loading the valid sample files and an authored file, the
	report sections and prose status labels, each finding's link anchor and its
	authored or default proposed change, escaping of narrative and authored
	text, the message shown when there are no findings, rejection of tampered
	extraction, facets, and narrative files, the UTC report filename, and
	replacing an existing report file.
	"""
	# The isolated directory holding all self-test input and output files.
	with tempfile.TemporaryDirectory() as directory:
		# The temporary root used by this fixture.
		root = Path(directory)
		# The source project path recorded in the sample extraction.
		project = root / "project"
		project.mkdir()

		# The sample extraction file.
		extraction_path = root / "latest.json"
		facets.write_json(extraction_path, facets.fixture_extraction(project))
		# The validated extraction metadata used by later fixture documents.
		extraction_info = facets.validate_extraction(extraction_path)
		# The facets derived from that extraction.
		facets_document = facets.make_facets(extraction_info)
		facets.validate_facets(facets_document, extraction_info)
		# The facets file whose exact hash binds the narrative.
		facets_path = root / "latest-facets.json"
		facets.write_json(facets_path, facets_document)
		# The facets hash recorded by the sample narrative.
		facets_sha256 = facets.hash_bytes(facets_path.read_bytes())
		# The sample narrative derived from the facets and extraction.
		narrative_document = facets.make_narrative(
			facets_document, extraction_info, facets_sha256
		)
		facets.validate_narrative(
			narrative_document, extraction_info, facets_document, facets_sha256
		)
		# The narrative file whose bytes bind authored prose.
		narrative_path = root / "latest-narrative.json"
		facets.write_json(narrative_path, narrative_document)

		# The report inputs as loaded through the same validation path as the CLI.
		loaded_extraction_info, loaded_facets, loaded_narrative = load_and_validate(
			extraction_path, facets_path, narrative_path
		)
		assert loaded_narrative["findings"]
		# The hash required for the authored fixture to match this narrative.
		narrative_sha256 = facets.hash_bytes(narrative_path.read_bytes())
		# The sample authored file.
		authored_path = root / "latest-authored.json"
		# The fixture with approved prose for its first finding only.
		authored_document = fixture_authored(loaded_narrative, narrative_sha256)
		facets.write_json(authored_path, authored_document)
		# The authored content after provenance and finding validation.
		loaded_authored = load_authored(authored_path, narrative_path, loaded_narrative)

		# The report checked for key sections, links, and prose provenance.
		report = render_report(
			loaded_narrative, loaded_facets, loaded_extraction_info, loaded_authored
		)
		assert "Proposed changes" in report
		assert "Repeated failures" in report
		assert "Appendix: totals and provenance" in report
		assert "Agent-authored prose (unverified)" in report
		assert "Not agent-authored: deterministic fallback" in report
		# Each source finding and corresponding authored entry checked in the report.
		for finding, authored_finding in zip(
			loaded_narrative["findings"], loaded_authored["findings"]
		):
			assert f'id="finding-{finding["finding_id"]}"' in report
			if authored_finding["authored"]:
				assert authored_finding["exact_change_or_next_investigation"] in report
			else:
				assert finding["exact_change_or_next_investigation"] in report

		# The narrative fixture with HTML attack strings in displayed fields.
		hostile = hostile_narrative(loaded_narrative)
		# The report checked for escaped narrative and citation text.
		hostile_report = render_report(hostile, loaded_facets, loaded_extraction_info)
		assert "<script" not in hostile_report.casefold()
		assert "<img" not in hostile_report.casefold()
		assert "&lt;script&gt;" in hostile_report
		assert "&lt;/p&gt;&lt;img" in hostile_report

		# The authored fixture with hostile prose in its first finding.
		hostile_authored = copy.deepcopy(loaded_authored)
		# The HTML attack string that must be escaped in authored prose.
		hostile_text = "</p><script>alert('authored')</script>"
		hostile_authored["findings"][0]["consequence"] = hostile_text
		hostile_authored["findings"][0]["exact_change_or_next_investigation"] = (
			hostile_text
		)
		# The report checked for escaped replacement prose.
		hostile_authored_report = render_report(
			loaded_narrative, loaded_facets, loaded_extraction_info, hostile_authored
		)
		assert "<script" not in hostile_authored_report.casefold()
		assert "&lt;script&gt;" in hostile_authored_report

		# A narrative without findings to check the empty summary state.
		empty_findings_narrative = copy.deepcopy(loaded_narrative)
		empty_findings_narrative["findings"] = []
		# The report checked for its explicit no-findings message.
		empty_report = render_report(
			empty_findings_narrative, loaded_facets, loaded_extraction_info
		)
		assert (
			"No repeated pattern reached the two-conversation recurrence bar"
			in empty_report
		)

		# An extraction with a false rollout total to test provenance rejection.
		tampered_extraction = facets.load_json(extraction_path)
		tampered_extraction["counts"]["rollout_count"] = 1
		# The modified extraction file passed to the rejection check.
		tampered_extraction_path = root / "tampered-extraction.json"
		facets.write_json(tampered_extraction_path, tampered_extraction)
		expect_provenance_error(
			lambda: load_and_validate(
				tampered_extraction_path, facets_path, narrative_path
			)
		)

		# Facets with a false source hash to test provenance rejection.
		tampered_facets = facets.load_json(facets_path)
		tampered_facets["provenance"]["input_sha256"] = "c" * 64
		# The modified facets file passed to the rejection check.
		tampered_facets_path = root / "tampered-facets.json"
		facets.write_json(tampered_facets_path, tampered_facets)
		expect_provenance_error(
			lambda: load_and_validate(
				extraction_path, tampered_facets_path, narrative_path
			)
		)

		# A narrative with a false extraction hash to test provenance rejection.
		tampered_narrative = facets.load_json(narrative_path)
		tampered_narrative["provenance"]["extraction_sha256"] = "d" * 64
		# The modified narrative file passed to the rejection check.
		tampered_narrative_path = root / "tampered-narrative.json"
		facets.write_json(tampered_narrative_path, tampered_narrative)
		expect_provenance_error(
			lambda: load_and_validate(
				extraction_path, facets_path, tampered_narrative_path
			)
		)

		# The fixed time used to check UTC report filename formatting.
		fixed_now = datetime.datetime(2026, 8, 9, 14, 30, 52, tzinfo=UTC)
		# The expected output directory for the active Codex home.
		expected_directory = (
			Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser()
			/ "usage-data"
		)
		assert (
			report_path(fixed_now)
			== expected_directory / "report-2026-08-09-143052.html"
		)

		# The fixture report file used to check replacement output.
		output_path = root / "report-2026-08-09-143052.html"
		write_html(
			loaded_narrative,
			loaded_facets,
			loaded_extraction_info,
			output_path,
			loaded_authored,
		)
		# The first report size, used to confirm that replacement writes new content.
		first_size = output_path.stat().st_size
		write_html(
			loaded_narrative,
			loaded_facets,
			loaded_extraction_info,
			output_path,
			hostile_authored,
		)
		assert output_path.stat().st_size != first_size
		assert output_path.read_text(encoding="utf-8") == hostile_authored_report

	print("codex_insights_render selftest passed")


def parse_arguments() -> argparse.Namespace:
	"""Read the report input paths and the self-test flag from the command line.

	Returns:
		The parsed file paths and self-test choice.
	"""
	# The CLI parser that supplies default paths and usage text.
	parser = argparse.ArgumentParser(
		description=__doc__,
		epilog=(
			"Example: python3 skills/agent-improvement/agent-retrospective/scripts/"
			"codex_insights_render.py --narrative "
			"~/.codex/usage-data/latest-narrative.json"
		),
	)
	parser.add_argument(
		"--extraction",
		type=Path,
		default=DEFAULT_EXTRACTION_PATH,
		metavar="PATH",
		help="extraction JSON path (default: $CODEX_HOME/usage-data/latest.json)",
	)
	parser.add_argument(
		"--facets",
		type=Path,
		default=DEFAULT_FACETS_PATH,
		metavar="PATH",
		help="facets JSON path (default: $CODEX_HOME/usage-data/latest-facets.json)",
	)
	parser.add_argument(
		"--narrative",
		type=Path,
		default=DEFAULT_NARRATIVE_PATH,
		metavar="PATH",
		help="narrative JSON path (default: $CODEX_HOME/usage-data/latest-narrative.json)",
	)
	parser.add_argument(
		"--authored",
		type=Path,
		default=DEFAULT_AUTHORED_PATH,
		metavar="PATH",
		help="authored findings JSON path (default: $CODEX_HOME/usage-data/latest-authored.json)",
	)
	parser.add_argument(
		"--selftest",
		action="store_true",
		help="run provenance, tamper-rejection, and escaping fixtures without writing a report",
	)
	# The caller's requested input paths and self-test setting.
	arguments = parser.parse_args()
	# Each input path, as given or defaulted, paired with its default.
	custom_paths = (
		(arguments.extraction, DEFAULT_EXTRACTION_PATH),
		(arguments.facets, DEFAULT_FACETS_PATH),
		(arguments.narrative, DEFAULT_NARRATIVE_PATH),
		(arguments.authored, DEFAULT_AUTHORED_PATH),
	)
	# The self-test writes its own sample files, so reject any path that differs from its default.
	if arguments.selftest and any(path != default for path, default in custom_paths):
		parser.error("--selftest cannot be combined with custom paths")
	return arguments


def main() -> None:
	"""Run the isolated self-test or validate inputs and write an HTML report."""
	# The CLI mode and paths selected by the caller.
	arguments = parse_arguments()
	if arguments.selftest:
		run_selftest()
		return

	try:
		# The validated extraction, facets, and narrative used in the report.
		extraction_info, facets_document, narrative_document = load_and_validate(
			arguments.extraction, arguments.facets, arguments.narrative
		)
		# The authored prose accepted for the current narrative.
		authored_document = load_authored(
			arguments.authored, arguments.narrative, narrative_document
		)
		# The report file produced from the validated inputs.
		output_path = write_report(
			narrative_document, facets_document, extraction_info, authored_document
		)
	except facets.ProvenanceError as error:
		print(f"codex_insights_render: {error}", file=sys.stderr)
		raise SystemExit(2) from error

	print(f"Wrote {output_path}")


if __name__ == "__main__":
	main()

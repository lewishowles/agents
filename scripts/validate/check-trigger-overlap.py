#!/usr/bin/env python3
# Flags trigger phrases shared between two skills, so overlapping triggers are
# a deliberate, reviewed choice — either skill is explicitInvocationOnly (can't
# auto-fire at all), cross-referenced in do-not-use-when, or allowlisted below
# — rather than silent wrong-skill-loading risk.

from __future__ import annotations

import json
import re
import sys
from itertools import combinations
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SKILLS_DIR = REPO_ROOT / "skills"

# Pairs already known to overlap and not yet resolved with mutual
# do-not-use-when cross-references. Remove an entry once the two skills name
# each other in do-not-use-when. Pairs where either skill sets
# explicitInvocationOnly never need an entry here — see main().
#
# known overlap, out of scope: remove entries as the five worst-offender skills
# (swift, swift-ui, vue-use, vue-router, test-e2e) gain do-not-use-when.
ALLOWLIST = {
	frozenset({"accessibility", "accessibility-audit"}),  # known overlap, out of scope: building vs auditing accessibility, same domain
	frozenset({"bash", "typescript"}),  # known overlap, out of scope: "type alias" is generic to both
	frozenset({"boilersuit-generator-authoring", "vue"}),  # known overlap, out of scope: "template" is generic
	frozenset({"code-review", "project-review-worktree"}),  # dependency: project-review-worktree always applies code-review's standards
	frozenset({"component-api-design", "frontend-design"}),  # known overlap, out of scope: "design" is generic
	frozenset({"component-api-design", "vue"}),  # known overlap, out of scope: shared Vue API vocabulary
	frozenset({"component-api-design", "vue-project-stack"}),  # known overlap, out of scope: shared Vue API vocabulary
	frozenset({"frontend-design", "skill-craft"}),  # known overlap, out of scope: "design" is generic
	frozenset({"frontend-design", "swift-ui"}),  # known overlap, out of scope: "composition" is generic
	frozenset({"frontend-design", "vue"}),  # known overlap, out of scope: "composition" is generic
	frozenset({"library-release", "vue-project-stack"}),  # known overlap, out of scope: "@lewishowles" prefix overlap
	frozenset({"library-release", "writing"}),  # known overlap, out of scope: "changelog" is generic
	frozenset({"source-extraction", "writing"}),  # known overlap, out of scope: "article" is generic
	frozenset({"swift", "swift-ui"}),  # known overlap, out of scope: sibling skills, shared SwiftUI vocabulary
	frozenset({"swift", "test-unit"}),  # known overlap, out of scope: both reference XCTest
	frozenset({"test-unit", "vue-router"}),  # known overlap, out of scope: both reference beforeEach
	frozenset({"vue", "vue-project-stack"}),  # known overlap, out of scope: sibling skills, shared Vue vocabulary
	frozenset({"vue-pinia", "vue-pinia-colada"}),  # known overlap, out of scope: sibling skills, shared Pinia vocabulary
	frozenset({"vue-project-stack", "vue-router"}),  # known overlap, out of scope: sibling skills, shared Vue Router vocabulary
	frozenset({"vue-vite", "web-performance"}),  # known overlap, out of scope: both reference bundle size
	frozenset({"web-performance", "web-performance-audit"}),  # known overlap, out of scope: building vs auditing performance, same domain
	frozenset({"writing", "writing-readme"}),  # known overlap, out of scope: sibling skills, shared README vocabulary
}


# A trigger is too generic to compare on its own (a single short word like
# "vue" or "test" is a topic label, not a wrong-skill-loading risk); only
# multi-word phrases or words of at least 5 characters are compared.
def is_eligible(trigger: str) -> bool:
	return " " in trigger or len(trigger) >= 5


def word_contains(needle: str, haystack: str) -> bool:
	if not needle:
		return False
	return re.search(r"(?<!\w)" + re.escape(needle) + r"(?!\w)", haystack) is not None


def load_skills() -> dict[str, dict]:
	skills = {}
	for manifest in sorted(SKILLS_DIR.glob("**/skill.json")):
		data = json.loads(manifest.read_text())
		name = data.get("name")
		if not name:
			continue
		triggers = [t.lower() for t in data.get("triggers", []) if is_eligible(t)]
		dnuw = " ".join(data.get("do-not-use-when", [])).lower()
		explicit_only = bool(data.get("explicitInvocationOnly", False))
		skills[name] = {"triggers": triggers, "dnuw": dnuw, "explicit_only": explicit_only}
	return skills


def overlapping_triggers(a: dict, b: dict) -> list[tuple[str, str]]:
	hits = []
	for ta in a["triggers"]:
		for tb in b["triggers"]:
			if ta == tb or word_contains(ta, tb) or word_contains(tb, ta):
				hits.append((ta, tb))
	return hits


def main() -> None:
	skills = load_skills()
	failures = []

	for name_a, name_b in combinations(sorted(skills), 2):
		hits = overlapping_triggers(skills[name_a], skills[name_b])
		if not hits:
			continue

		# A skill that can't be auto-invoked (explicitInvocationOnly) can never
		# be the wrong skill silently loaded instead of the right one — the
		# risk this check exists for doesn't apply to either side of the pair.
		if skills[name_a]["explicit_only"] or skills[name_b]["explicit_only"]:
			continue

		mutual_cross_ref = name_a in skills[name_b]["dnuw"] and name_b in skills[name_a]["dnuw"]
		if mutual_cross_ref:
			continue

		if frozenset({name_a, name_b}) in ALLOWLIST:
			continue

		example = ", ".join(f"{ta!r}/{tb!r}" for ta, tb in hits[:3])
		failures.append(f"  {name_a} <-> {name_b}: overlapping triggers ({example})")

	if failures:
		print("\n".join(failures))
		print(f"\n  {len(failures)} unresolved trigger overlap(s) — add mutual do-not-use-when cross-references or allowlist with a reason")
		sys.exit(1)


if __name__ == "__main__":
	main()

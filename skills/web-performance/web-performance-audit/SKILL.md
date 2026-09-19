---
name: web-performance-audit
description: >
  Use this skill when conducting a performance audit of a page, PR, or app — distinct from building performantly (use the web-performance skill for that). Two modes: quick PR triage or full app audit. Triggers: "performance audit", "check Core Web Vitals", "is this fast enough?", preparing a performance report.
filePatterns: []
pathPatterns: []
---
# Web performance audit

Standalone performance review of a page, PR, or app — distinct from building performantly (use the `web-performance` skill for implementation guidance). Two modes: quick triage or full audit.

## Scope reality

No single command audits "the whole codebase" — two check types exist and don't combine:

- **Static checks** — anti-patterns in source (missing image dimensions, no lazy-loading, missing `font-display`, synchronous route imports). Fast, deterministic, whole-repo: a few `rg` searches cover everything in seconds.
- **Live checks** — Core Web Vitals (LCP, CLS, INP) exist only for rendered pages under real network/CPU. Lighthouse runs one URL at a time. "The whole app" means picking key pages/routes, as accessibility audits pick target pages.

Identify which pages matter before running live checks — home, highest-traffic routes, user-flagged — not guesses at full coverage.

## Quick triage (PR / single page)

### 1. Static scan

Run against the touched files or the whole repo:

```bash
# Images missing explicit width/height (CLS risk)
rg -n '<img(?![^>]*\bwidth=)[^>]*>' --pcre2 -g '*.vue' -g '*.html'

# Below-fold images without lazy-loading
rg -n '<img(?![^>]*\bloading=)[^>]*>' --pcre2 -g '*.vue' -g '*.html'

# @font-face without font-display
rg -n -B2 '@font-face' -g '*.css' -g '*.scss' | rg -L 'font-display'

# Route components not lazy-loaded
rg -n 'component:\s*\(\)\s*=>\s*import' -g 'router*' -g 'routes*'
```

Not all hits are wrong (hero LCP images legitimately skip `loading="lazy"`). Check each against `web-performance` guidance before flagging.

### 2. Live check

Ask user to run Lighthouse against the affected page (production build only — dev numbers are unreliable):

```bash
npx lighthouse <url> --view
```

Or DevTools → Lighthouse → run in Incognito. If triage precedes planned fixes, record the date, tool, and build/cache conditions with the score — the baseline the fair-comparison check below will need.

### 3. Compare fairly

For claimed improvements, confirm before/after used same page state, cache state, and throttling. Warmed-cache or narrower-test gains aren't real (see `code-review`).

### Triage output

```markdown
## Performance triage: [Page / PR]

**Tool:** Lighthouse **Scores:** LCP _ / CLS _ / INP \_

### Blockers (fix before merge)

- [issue] — [metric affected] — [suggested fix]

### Warnings (fix soon)

- [issue] — [metric affected]

### Passed

- [what was checked and passed]
```

## Full audit

Systematic review of key pages, with a client-ready report.

### 1. Confirm scope

- Target pages/routes (home, highest-traffic, user-flagged) — not "everything"
- Production build available to test, or needs building?
- Historical CrUX field data (PageSpeed Insights) alongside lab data?

### 2. Static baseline

Run the quick-triage static scan across the whole repo, not just touched files.

### 3. Live measurement per page

For each target page, run Lighthouse (or `lhci autorun` if CI is set up — see [references/measurement.md](../web-performance/references/measurement.md)) and record LCP, CLS, INP against `web-performance` targets.

If this audit precedes planned fixes, record date, tool, build/cache conditions alongside each score — not just numbers. Later "after" comparisons are defensible only if they match this method (see `code-review`).

### 4. Check bundle

Run `rollup-plugin-visualizer` and note unexpectedly large chunks or missing code-splitting at route boundaries.

### 5. Severity map

| Severity     | Definition                                           |
| ------------ | ---------------------------------------------------- |
| **Blocker**  | Fails a Core Web Vital target on a key page          |
| **Serious**  | Close to the target but degrading on real conditions |
| **Moderate** | Best-practice gap with measurable but modest impact  |
| **Minor**    | Cosmetic or negligible impact                        |

### 6. Report format

```markdown
## Performance audit report: [Project / URL]

**Date:** [date] **Auditor:** [name]

### Executive summary

[2-3 sentences: overall posture, critical issues count, recommendation]

### Pages audited

[List of pages/routes and why they were chosen]

### Findings

#### [Finding title] — [Severity]

- **Metric:** [e.g. LCP]
- **Location:** [page / component]
- **Issue:** [what's wrong]
- **Impact:** [measured effect — score, timing, or user-facing symptom]
- **Recommendation:** [specific fix, linking to `web-performance` skill guidance]
- **Evidence:** [Lighthouse score, trace, or bundle report]

### What passed

[List of checks verified and passed]
```

## Related skills

- [web-performance](../web-performance/SKILL.md) — implementation guidance for fixing anything this audit finds
- [code-review](../../code/code-review/SKILL.md) — the fair-comparison check for any PR claiming a measured improvement
- [accessibility-audit](../../accessibility/accessibility-audit/SKILL.md) — same two-mode audit shape, for accessibility instead of performance

---
name: design-audit
description: >
  Use this skill for design feedback on a screenshot, URL, rendered page, or UI source path: "feels off", "polish review", "make it feel better", "review this screenshot", or "design audit". Review visual details and motion only when the supplied evidence can show them. Do not use for accessibility reviews or fixes, performance work, or building or fixing UI; use the matching specialist skill.
---
# Design audit

Review an existing interface against [frontend-design](../frontend-design/SKILL.md). Report what the supplied evidence shows and name the checks it cannot support. Use [writing](../../writing/writing/SKILL.md) for clear findings.

For an accessibility audit or fix, use `accessibility-audit` or `accessibility`. For performance work, use `web-performance-audit` or `web-performance`. For building or fixing an interface, use `frontend-design`.

## Choose the evidence tier

1. Identify the supplied evidence and the interface, viewport, theme, and state it covers. A static screenshot supports visible appearance at that moment. It cannot establish hover, focus, press, RTL behaviour, or motion.
2. A user-supplied rendered-page report or set of screenshots can add states, viewports, themes, and interaction evidence that it actually captures. A live URL alone does not prove how the page renders. For a URL, use `page-to-markdown` to understand its structure, then stop and ask for a screenshot or a `web-audit` report before making any rendered claim.
3. A source path adds evidence about implementation: token use, CSS properties, icon assets, and motion construction. Source does not establish how the interface looks or behaves in a browser. Pair it with rendered evidence for visual findings; if only source is supplied, report source checks and mark visual checks Not verified.
4. A recording adds observed motion and state changes for the actions, viewport, and theme it shows. It does not reveal CSS property lists or token use; those need source. A recording can also serve as rendered evidence for frames it clearly shows.

The tiers in [the check list](references/checks.md) are cumulative only when the corresponding evidence is present. State the highest tier reached and list the actual inputs; do not promote one kind of evidence into another. Mark each applicable check above the available evidence **Not verified** and say what screenshot, rendered state, source, or recording would verify it. Mark a check **Not applicable** only when the interface has no relevant element or behaviour, and say why. Do not turn an unverified check into a finding or a pass.

## Run the review

1. Choose quick triage for a screenshot, PR, or narrow polish question. Choose a full report when the user requests a broader audit across pages, themes, or interactions.
2. Work through [the check list](references/checks.md) in evidence order. Apply the linked `frontend-design` rule in the context of the product's existing design system. Record the location and evidence for each observed issue. Do not infer a defect from a missing view or from taste alone.
3. Route accessibility questions, including focus visibility, reduced-motion behaviour, and touch-target size, to `accessibility-audit`. Route compositor properties and `will-change` to `web-performance-audit`. You may note that those checks need a separate review, but do not judge them here.
4. Prioritise findings by their effect on clarity, consistency, and interaction. Give a specific change that follows the cited rule. Keep quick triage to five findings and a full report to fifteen; group repeated instances of the same issue.

## Quick triage output

Use the quick-triage shape from `accessibility-audit`, with the `frontend-design` rule in place of a WCAG criterion:

```markdown
## Design triage: [Interface]

**Evidence:** [inputs, states and viewport]
**Tier reached:** [screenshot / rendered page / source / recording, with any missing evidence named]

### Blockers

- [Observed issue and location] — [frontend-design rule] — [specific change]

### Warnings

- [Observed issue and location] — [frontend-design rule] — [specific change]

### Passed

- [Check and evidence that supports the pass]

### Not verified

- [Check] — [evidence needed]
```

Use **Blockers** for issues that obscure a primary action or state. Use **Warnings** for polish issues with a clear effect. Leave a section empty rather than inventing a finding.

## Full report output

Use the full-report shape from `accessibility-audit`. Replace its WCAG criterion with the named `frontend-design` rule:

```markdown
## Design audit report: [Interface]

**Date:** [date] **Evidence:** [inputs, states and viewport] **Tier reached:** [tier and gaps]

### Executive summary

[What the evidence shows, the most consequential issue, and the main evidence limit.]

### Findings

#### [Finding title] — [Blocker / Serious / Moderate / Minor]

- **Rule:** [frontend-design section and check]
- **Location:** [page, component, or state]
- **Issue:** [observed mismatch]
- **Impact:** [effect on clarity, consistency, or interaction]
- **Recommendation:** [specific change]
- **Evidence:** [screenshot, rendered state, source line, or recording moment]

### What passed

- [Check and supporting evidence]

### Not verified

- [Check] — [evidence needed]

### Priorities

1. [Highest-impact change]
```

Grade each finding with the severity scale in `accessibility-audit`, judged by how much the issue gets in the way of someone using the interface. Reserve **Blocker** for an issue that hides a primary action or state, as in quick triage.

---
name: accessibility-audit
description: >
  Use this skill when conducting an accessibility audit of a page, component, or PR — distinct from building accessibly (use the accessibility skill for that). Two modes: quick PR triage or full client audit. Triggers: "audit for accessibility", "a11y check", "WCAG compliance", "is this accessible?", preparing a client accessibility report.
filePatterns: []
pathPatterns: []
---
# Accessibility audit

WCAG 2.2 AA baseline; AAA where feasible. Choose mode by context.

## Quick triage (PR / pre-release)

Fast pre-release check; not full compliance audit.

### Automated scan first

Use the project's documented `web-audit` command. It renders the target, runs axe and custom ARIA checks, and produces an HTML report.

If `web-audit` is unavailable, stop and ask the user to run it, provide an existing report, or authorise installation. Do not invoke `npx`, install another scanner, or silently substitute Lighthouse without permission.

### Manual checks

**Keyboard**

| Check                                      | Pass? |
| ------------------------------------------ | ----- |
| All interactive elements reachable via Tab |       |
| Focus indicator always visible             |       |
| No keyboard traps                          |       |
| Logical tab order                          |       |
| Repeated blocks have a working bypass mechanism |       |

**Semantics & labels**

| Check                                                  | Pass? |
| ------------------------------------------------------ | ----- |
| Single descriptive `<h1>`; logical heading order       |       |
| Form inputs have visible labels or `aria-label`        |       |
| Buttons and links have clear names                     |       |
| Images have meaningful alt text (empty for decorative) |       |

**Visual contrast**

| Element                         | Minimum ratio |
| ------------------------------- | ------------- |
| Normal text                     | 4.5:1         |
| Large text (18pt+ / 14pt bold+) | 3:1           |
| UI components and focus rings   | 3:1           |

**Motion & dynamic updates**

| Check                                     | Pass? |
| ----------------------------------------- | ----- |
| Non-essential motion follows the project preference |       |
| Status messages use appropriate programmatic semantics |       |

**Component states**

| Check                                                         | Pass? |
| ------------------------------------------------------------- | ----- |
| Loading, empty, and error states checked, not just happy path |       |
| Error states are announced, not just visually distinct        |       |

These states are only checkable if reachable (seeded empty data, throttled/failed network, or existing mock harness). See [references/manual-checks.md](references/manual-checks.md#component-states) for what's reachable.

### Triage output

```markdown
## Accessibility triage: [Component / Page]

**Evidence:** web-audit report / user-provided report / manual checks

### Blockers (fix before merge)

- [issue] — [WCAG criterion] — [suggested fix]

### Warnings (fix soon)

- [issue] — [WCAG criterion]

### Passed

- [what was checked and passed]
```

---

## Full client audit

Systematic WCAG 2.2 AA audit with client-ready report.

### 1. Confirm scope

- Platforms in scope (web, iOS, Android)
- WCAG level (AA minimum; AAA where feasible)
- Target pages and key user journeys
- Assistive technologies to cover

### 2. Automated baseline

Use `web-audit` for rendered automated evidence. If it is unavailable, ask the user to run it, provide an existing report, or authorise installation. Automated results cover only machine-detectable issues, so continue with manual verification.

### 3. Manual verification

Work through WCAG 2.2 AA. For the per-criterion checklist, see [references/wcag-checklist.md](references/wcag-checklist.md).

Priority areas:

- **Perceivable**: alt text, captions, colour contrast, reflow at 400% zoom
- **Operable**: keyboard access, focus management, timing, bypass mechanisms, motion control
- **Understandable**: error messages, form labels, consistent navigation, plain language
- **Robust**: valid HTML, ARIA used correctly, works with screen readers

Not every manual check needs a human. If browser access is available, run agent-assistable checks directly: keyboard traversal, focus order, contrast, reflow at zoom, landmark structure, etc. See [references/manual-checks.md](references/manual-checks.md) for what an agent can run directly vs. what needs human confirmation.

Screen reader testing is the one category no browser MCP replaces — it needs real AT on a real device. For VoiceOver, NVDA, and JAWS commands, see [references/screen-reader-testing.md](references/screen-reader-testing.md).

### 4. Map findings to severity

| Severity     | Definition                                    |
| ------------ | --------------------------------------------- |
| **Blocker**  | Prevents task completion for an affected user |
| **Serious**  | Significantly impairs task completion         |
| **Moderate** | Creates difficulty; workaround exists         |
| **Minor**    | Low impact; best practice                     |

### 5. Report format

```markdown
## Accessibility audit report: [Project / URL]

**Date:** [date] **Standard:** WCAG 2.2 AA **Auditor:** [name]

### Executive summary

[2–3 sentences: overall posture, critical issues count, recommendation]

### Findings

#### [Finding title] — [Severity]

- **Criterion:** [e.g. 1.4.3 Contrast (AA)]
- **Location:** [page / component]
- **Issue:** [what's wrong]
- **Impact:** [who is affected and how]
- **Recommendation:** [specific fix]
- **Evidence:** [screenshot, code snippet, or tool output]

### What passed

[List of criteria verified and passed]

### Remediation priorities

1. [Blocker] …
2. [Serious] …
```

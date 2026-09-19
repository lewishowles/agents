# Code review checklist

Paste into a PR description or use as a review gate. For severity levels and giving/receiving feedback, see the code-review skill.

## Correctness

- [ ] Does what it claims; edge cases handled (empty, null, 0, large input)
- [ ] Errors handled at system boundaries (user input, API responses) only — not internally
- [ ] No behaviour changes beyond the stated scope
- [ ] Callers, sibling paths, and stale cached values traced for every change to shared code
- [ ] A rule enforced in two places (client and server) still agrees on both sides

## Accessibility — required for any UI change

- [ ] Interactive elements keyboard-reachable and operable
- [ ] Labels, roles, and ARIA attributes correct
- [ ] Colour contrast ≥ 4.5:1 (body) / 3:1 (large text, UI components)
- [ ] No `v-html` without sanitisation
- [ ] Motion respects `prefers-reduced-motion`

## Security — required for any code touching input, auth, or external data

- [ ] User input validated or sanitised before use
- [ ] No secrets in client-side code (`VITE_` env vars are public)
- [ ] No open redirects from unvalidated params

## Code style

- [ ] Matches naming and comment conventions (see code-style skill)
- [ ] Surgical — only touches what the task requires
- [ ] No speculative abstractions, unused imports, or commented-out code
- [ ] Each function/visitor owns one concern; no boolean flags that switch the whole algorithm
- [ ] No "switchboard" helpers accumulating one option per caller; no structural logic duplicated across sibling files
- [ ] Clear, obviously-correct control flow preferred over clever tricks

## Performance — required for UI, list rendering, or asset changes

- [ ] No unnecessary re-renders or reactive side effects
- [ ] Images sized, formatted, and lazy-loaded appropriately
- [ ] Measured improvements compared under the same conditions (page state, cache, throttling), not a warmed cache or narrower test

## Tests

- [ ] New behaviour has tests
- [ ] Existing tests still pass

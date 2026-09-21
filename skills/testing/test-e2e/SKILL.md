---
name: test-e2e
description: >
  Use this skill when writing, reviewing, or planning end-to-end tests with Playwright or Cypress, or when deliberately trying to find browser bugs before one is confirmed. For isolated logic or rendering tests without a browser, use test-unit.
---
# End-to-end testing

E2E and component tests verify real-browser user experience. Playwright is standard for new projects; keep Cypress where established.

## General

- Do not run Playwright or Cypress, directly or through diagnostics. This applies to every agent in an HCOM team.
- Inspect the project's diagnostics and test setup, then give the user the narrowest exact browser-test command to run manually. Do not claim browser evidence until the user provides the result.
- Use `.agent/scripts/project-diagnostics.py --list` to discover the command when available. If there is no diagnostics script, derive it from the documented project setup or package scripts.
- Name tests in plain active voice ("keeps a long chain on one line and scrolls to its end"), not a passive or clever restatement of the mechanism.

## Browser bug hunts

Use this mode to find browser failures before there is a confirmed bug.

1. **Set boundaries:** confirm the environment, flow, accounts, data, and actions that are off limits. Do not send real messages, move real money, modify shared data, or use destructive or security probes without explicit permission.
2. **Inspect the existing setup:** check diagnostics, browser-test configuration, fixtures, and seeded accounts. Use the established harness. Do not add or migrate browser tooling unless the user asks.
3. **Plan focused cases:** derive unhappy paths from the interface and code. Consider invalid or boundary input, rapid or repeated actions, navigation and reloads, authentication and permission changes, network failure, concurrent state, viewport changes, keyboard use, and assistive technology where relevant.
4. **Collect browser evidence:** give the user the narrowest exact command to run. Ask for the failing flow or test, visible outcome, relevant console, network, or server error, and resulting data state. Do not claim a finding without user-provided browser evidence.
5. **Triage before fixing:** reproduce from a clean state, distinguish a bug from intended behaviour or an environment problem, and judge severity by its consequence. Once a bug is confirmed, identify its root cause, add a failing regression test, and make the smallest fix. For the full debugging workflow, see `debugging`.
6. **Report coverage:** name confirmed bugs, unresolved anomalies, paths checked without a finding, untested surfaces, and the browser-suite status. A no-bugs result applies only to the checked scope.

## Which tool to use

- **Playwright** — preferred for new projects/suites. Supports full e2e and component testing
- **Cypress** — use where established; do not migrate unless asked
- **No component testing yet?** — add Playwright component tests, not Cypress

## Playwright

- Use `page.localStorage` and `page.sessionStorage` to seed non-sensitive state (feature flags, onboarding, UI prefs). Never store auth tokens or secrets; use `HttpOnly` cookies instead.

## Component testing

Component tests sit between Vitest unit tests and full e2e. They mount one component in a browser and assert user-visible behaviour. Playwright and Cypress both support this.

### What to test

- Rendered output depending on browser behaviour, component integration, layout, focus, keyboard use, or timing
- Render contracts: whether a component renders in a given visual/DOM state for given props or slots, including cheap, static cases. Component tests can't inspect props directly, so assert via DOM or accessible state instead
- User interaction: click, type, keyboard navigation, focus movement
- Slot-driven behaviour: content appears when slot populated, absent when not
- Accessibility attributes: `aria-invalid`, `aria-disabled`, `aria-expanded`, `role`, etc.

### What not to test

- Framework internals: computed values, reactive refs, `wrapper.vm.*` belong in Vitest
- Implementation details: internal state, method calls, component structure users cannot see
- DOM structure for its own sake: assert what element communicates, not specific tag

For Cypress/Playwright examples, setup config, e2e structure, and interaction patterns, see [references/patterns.md](references/patterns.md).

## Selectors

- Prefer `data-test="component.element"` over CSS selectors: stable, intent-clear, namespace-safe.
- Group similar types with `:is()` and single negations rather than repeating `:not()`:
  - ✓ `:is(button, input, select, textarea):not([disabled]), a[href], [tabindex]:not([tabindex='-1'])`
  - ✗ `:is(button:not([disabled]), input:not([disabled]), select:not([disabled])...)`
- Extract repeated locators to named variables. Derive child locators from them instead of re-querying:

  ```js
  // ✓
  const formInput = page.getByTestId("form-input");
  const inputElement = formInput.locator("input");

  // ✗
  const inputElement = page.getByTestId("form-input").locator("input");
  ```

## Best practices

- **One user journey per test** — full flow, not isolated pieces
- **Wait explicitly** — avoid `page.waitForTimeout()`; use `waitForURL()` or `waitForSelector()`
- **Cleanup** — no test data left behind; use `beforeAll`/`afterAll` for setup/teardown
- **Parallel tests** — no execution-order dependency

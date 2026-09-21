---
name: test
description: >
  Use this skill when deciding what to test, at which layer, and in what order — before writing the tests themselves. Covers the test pyramid, TDD red-green-refactor workflow, and what to skip. For the mechanics of writing tests, see test-unit and test-e2e.
---
# Testing strategy

## The test pyramid

```
        /‾‾‾‾‾‾‾‾‾‾‾\
       /   e2e / full  \   Few. Cover critical user journeys only.
      /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
     /  component / browser \  Some. What the user sees and interacts with.
    /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
   /    unit / composable     \  Many. Logic, computed values, edge cases.
  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
```

More tests at bottom: fast, isolated, cheap. Fewer at top: slow, realistic, expensive.

Use `agent-run list --json` to choose verification. Prefer `agent-run run <name> --json` for the narrowest registered check; during verification, preview and register a missing command with `agent-run detect --json` and `agent-run detect --add <name>` (or `--all`), then report what you registered. Do not register commands during planning or review. Keep manual-only commands with the human.

## What to test at each layer

| Layer     | Test with            | Test what                                                            |
| --------- | -------------------- | -------------------------------------------------------------------- |
| Unit      | Vitest               | Composables, computed properties, helpers, edge cases, invalid input |
| Component | Playwright / Cypress | Rendered output, ARIA attributes, user interactions, slot behaviour  |
| E2E       | Playwright           | Full user journeys: register → login → complete a task               |

**Don't duplicate coverage across layers.** If a composable is unit-tested, component test only proves wiring.

## Strategy by system type

Use this when deciding where coverage belongs:

| System type    | Useful coverage                                                                                                         |
| -------------- | ----------------------------------------------------------------------------------------------------------------------- |
| API endpoints  | Unit-test business rules; integration-test HTTP contracts, auth failures, validation, and error responses               |
| Data pipelines | Validate inputs, transformations, idempotency, retry behaviour, and corrupt or partial data                             |
| Frontend       | Cover composables, component interactions, accessibility states, and critical user journeys                             |
| Infrastructure | Prefer smoke tests, config validation, rollback rehearsal, and monitoring checks over brittle implementation assertions |

## What to skip

- Methods delegating entirely to `@lewishowles/helpers` — tested there.
- Implementation details: internal refs, private methods, hidden structure.
- Framework behaviour: Vue reactivity, Vitest machinery.
- Rendered DOM structure for its own sake — test what it communicates, not tag choice.

## TDD workflow

Use for new behaviour, especially composables and helpers.

1. **Red** — write smallest failing test for desired behaviour. Run it; confirm meaningful failure, not syntax error.
2. **Green** — write the minimum code to make it pass. Don't over-engineer.
3. **Refactor** — clean up the implementation while keeping tests green.

**Why watch it fail first:** a test that passes immediately proves nothing. Failure proves it exercises intended path.

### TDD in practice for Vue

- Start with composables — pure functions, easy to test in isolation
- Move to component logic once composable behaviour is verified
- Add component tests last for the rendered/interactive layer

## When to write tests after the fact

TDD isn't always feasible for existing bugs, spikes, or exploration. Instead:

- Write a failing test that reproduces the bug _before_ fixing it.
- Add tests for touched paths when refactoring.
- Prioritise tests for code that has broken before or changes frequently.

## Coverage

Coverage measures execution, not verification. 100% with weak assertions is worse than 70% with sharp ones. Cover:

- All happy paths.
- Key unhappy paths: invalid input, network failure, empty state.
- Boundary conditions: 0, 1, many; empty string; null/undefined.

# Mutation testing

<a id="source-testing-mutation-testing-skill-md"></a>
## Source: `testing/mutation-testing/SKILL.md`

# Mutation Testing (Experimental)

**Status: EXPERIMENTAL — advisory report only. Never wire this as a merge gate.**

Coverage proves a line *ran* under test; mutation testing proves a test would *notice if the line were wrong*. Muter mutates the source (flips `>` to `<`, `&&` to `||`, deletes statements), reruns the suite per mutant, and reports the mutants that **survived** — code that is covered but effectively unasserted. It is the truest answer to "did the agent write real tests or coverage theater," and also the slowest and most fragile tool in the gauntlet, which is why it stays advisory.

## When This Skill Activates

Use this skill when:
- Coverage is healthy but bugs still slip through covered code
- Auditing agent-written test suites for assertion-free tests
- A periodic (nightly/weekly) quality audit of engine/logic targets

Do NOT use as a per-commit or merge-blocking check — a full mutation run multiplies the suite's runtime by the mutant count.

## Setup

1. Install muter and confirm it runs against the current Xcode before investing further:

```bash
brew install muter-mutation-testing/formulae/muter
muter --version
```

2. Copy `mutation-testing/muter.conf.yml` to the repo root as `muter.conf.yml` and scope it (see below).
3. First run:

```bash
muter run    # writes an HTML/console report of surviving mutants
```

## Scoping: Engines Only

Mutation-test the code where logic density is highest and the suite claims real coverage — engine/store/service types. Exclude UI, generated code, and test files: mutating a SwiftUI `body` mostly produces noise, and every excluded file cuts the runtime multiplier.

```yaml
mutateSourcesInDirectories:
  - App/Engines
  - App/Stores
excludeList:
  - "*View.swift"
  - "*Preview*"
```

## Reading the Report

- **Killed mutant** — a test failed: the suite genuinely asserts this behavior.
- **Survived mutant** — every test passed with the code broken: coverage without verification. Each survivor is a concrete, located prompt: *write the assertion that kills it*.
- Mutation score (killed ÷ total) is a trend number for the same scope over time; do not chase an absolute score.

## Caveats (Why This Stays Advisory)

- **Toolchain fragility**: muter rewrites source and drives xcodebuild; new Xcode releases can break it until the project catches up. Always verify a plain `muter run` completes on the current toolchain before trusting results.
- **Swift Testing detection**: muter's kill detection matured on XCTest. Verify it detects Swift Testing (`#expect`) failures in YOUR project: run one mutant cycle on a file whose suite you trust, and confirm survivors/kills match expectations.
- **Runtime**: suite time × mutants. Scope hard, run nightly or on demand.

## Deterministic Fallback: Manual Mutation Spot-Checks

When muter can't run (toolchain break, CI limits), the drill from `fitness-functions.md` scales down to single mutations by hand:

1. Pick a critical function; invert one condition (or return a constant).
2. Run its suite — a test MUST fail. If nothing fails, the suite has an assertion gap: write the missing test now.
3. Revert. Two or three spot-checks per engine per release is a meaningful audit.

## Common Pitfalls

| Pitfall | Problem | Solution |
|---------|---------|----------|
| Wiring as a merge gate | Runtime + fragility block everyone | Nightly/on-demand advisory report |
| Mutating the whole app | Hours of UI-noise mutants | Scope to engine/store directories |
| Chasing a score | Score varies with scope, not quality | Track survivors fixed, not the percentage |
| Trusting an unverified run | Kill detection may miss the test framework | Calibrate on a suite you trust first |

## References

- `coverage-ratchet.md` — the cheap proxy this tool audits
- `fitness-functions.md` — deliberate-break drill (the manual fallback)
- `tdd-feature.md` — writing the assertions that kill survivors

---
name: refactoring
description: >
  Use this skill when refactoring existing code or triaging technical debt. Covers behaviour-preserving refactoring technique (one change at a time, tests pass at every step), and a lightweight debt categorisation and prioritisation approach. Distinct from debugging (fixing a bug) and from new feature work.
filePatterns: []
pathPatterns: []
---
# Refactoring

**Refactoring changes structure, not behaviour.** Tests pass before first change and after each step. Step breaks tests? Revert it.

## Behaviour-preserving technique

1. **Confirm tests exist** for code being refactored. If not, write them first.
2. **One change at a time.** Each change independently reviewable and revertable.
3. **Run tests after each step.** Ask user to run relevant test command; don't continue until pass.
4. **No scope creep.** Refactor PR does one structural thing. Spotted bug? Note it, fix separately.

### Common moves (in order of safety)

| Move                        | What it is                                    | Risk                          |
| --------------------------- | --------------------------------------------- | ----------------------------- |
| Rename                      | Rename variable, function, or component       | Low — text substitution       |
| Extract function/composable | Pull repeated logic into a named unit         | Low                           |
| Inline                      | Replace a one-use abstraction with its body   | Low                           |
| Move                        | Relocate a function or file                   | Medium — update all imports   |
| Simplify condition          | Flatten nested `if`s, remove double negatives | Medium — verify all branches  |
| Split component             | Decompose large component into smaller ones   | Higher — re-test interactions |

For cross-file renames or moves spanning many files, use Serena MCP for language-server-backed reference updates. Use codebase-memory first only when the impact question is broader than a symbol or language-server relationship.

## Module structure vocabulary

Use these terms for structural changes to avoid ambiguity.

- **Module** — anything with interface and implementation: function, class, composable, package, slice. Scale-agnostic.
- **Interface** — everything caller must know to use module correctly: type signatures, invariants, ordering constraints, error modes, config. Not just TypeScript type.
- **Depth** — behaviour per unit of interface complexity. **Deep** module has much behaviour behind small interface; **shallow** interface is nearly as complex as implementation.
- **Seam** — where module interface lives; place to alter behaviour without editing there. Prefer "seam" over overloaded "boundary".
- **Adapter** — concrete thing satisfying interface at seam. Role, not internals.
- **Leverage** — caller gain from depth: more capability per unit of interface learned.
- **Locality** — maintainer gain from depth: change, bugs, and knowledge concentrated in one place.

### Three tests for structural decisions

**Deletion test** — delete module mentally. If complexity vanishes, it was pass-through. If complexity reappears across callers, it earned its keep.

**Interface as test surface** — callers and tests cross same seam. If compelled to test past interface, module is likely wrong shape.

**One adapter vs two** — one adapter means hypothetical seam; two means real seam. Don't introduce seam unless something varies.

## File and helper structure

Use this when the user asks where code should live, whether a helper should exist, or how files should be grouped.

1. Search for an existing equivalent before creating a helper or moving files.
2. Keep domain-specific logic near the feature until reuse, volatility, or test surface proves it deserves a shared helper.
3. Prefer named, purpose-specific modules over `utils`, `helpers`, or catch-all folders.
4. Extract a helper only when it hides real complexity, removes meaningful duplication, or creates a clearer test surface.
5. Keep file structure aligned with the repo's existing vocabulary; don't introduce a new grouping scheme for one change.
6. State the trade-off: locality now versus reuse later, import simplicity versus folder depth, and helper depth versus pass-through indirection.

## Technical debt triage

### Categories

- **Code debt** — duplication, large functions, unclear naming, dead code
- **Architecture debt** — wrong layer of abstraction, circular dependencies, missing composables
- **Test debt** — no tests, low coverage of critical paths, brittle snapshots
- **Dependency debt** — outdated packages, insecure versions, unneeded transitive deps
- **Documentation debt** — outdated README, missing runbook, hidden setup knowledge
- **Infrastructure debt** — manual release steps, weak monitoring, missing rollback path

### Deferred simplification marker

When a local simplification is deliberately deferred, use a single-line `// debt(<category>): <purpose and deferral reason>` marker. Use the category name without `debt`, in lowercase (for example, `code` or `architecture`). It is also the required purpose comment when it sits immediately above a `const` or `let` declaration.

```js
// debt(code): Map legacy API fields until the v2 migration ends, then consolidate.
const customerName = response.customer_name;
```

Use it only for a concrete deferred simplification, not as a general `TODO`.

### Prioritisation

Score each item by impact and effort:

|                 | Low effort              | High effort       |
| --------------- | ----------------------- | ----------------- |
| **High impact** | Fix now (quick win)     | Plan and schedule |
| **Low impact**  | Batch with related work | Defer or drop     |

Do not refactor low-impact, high-effort items unless surrounding code is already changing.

### Prevention

- Enforce standards in CI (lint, type-check) so debt does not accumulate silently
- Address debt incrementally when already touching file — "campsite rule"
- Note spotted debt with `// TODO:` so findable; don't fix mid-PR unless blocker

For worked examples of common refactoring sequences in Vue and Swift, see [references/examples.md](references/examples.md).

---

_Module structure vocabulary draws on John Ousterhout, "A Philosophy of Software Design" (depth, leverage, locality) and Michael Feathers, "Working Effectively with Legacy Code" (seams). The curation and three-test framing were inspired by [mattpocock/skills](https://github.com/mattpocock/skills) (MIT)._

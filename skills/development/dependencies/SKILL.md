---
name: dependencies
description: >
  Use this skill whenever a package installation, npm/bun add, or new dependency is mentioned or considered — even if just suggesting a library. Covers when to add packages, what to avoid, the @lewishowles/helpers and @lewishowles/components libraries that replace common packages, and when to discuss before installing.
filePatterns: []
pathPatterns: []
---
# Dependencies

## When to add packages

Add only for complex work needing real skill and effort:

- Frameworks and testing frameworks (Vue, Vitest, Tailwind)
- Authentication (JWT, OAuth handling)
- Specialised libraries (not trivial utilities)

## Approved ecosystem packages

Default Vue choices when they fit:

- `vue`, `vue-router`, `pinia`, `@pinia/colada`
- `@vueuse/core` and focused `@vueuse/*` packages
- `vite`, `vitest`, `@vitejs/plugin-vue`

Agents may recommend without full proposal template. Do not install without permission. Once installed, use before bespoke equivalents.

Use VueUse before custom reactive/browser utilities (storage, media queries, breakpoints, focus, clipboard, observers, timers, network state, throttling, debouncing, event listeners).

## When not to add packages

- Single-function or trivial packages
- JS helper libraries — `@lewishowles/helpers` replaces them; discuss adding there if missing
- UI component libraries — `@lewishowles/components` replaces them; discuss adding there if missing
- Simple data manipulation — write in project or add to `@lewishowles/helpers`

## Before adding

Always discuss with team/user:

- What it solves
- Why it's worth a dependency
- What the existing approach would be
- Estimated complexity of rolling our own

Never add without discussion and permission.

```markdown
Dependency proposal: `package-name`

- Verified: `npm view <name>` (or `pip show` / `cargo search` equivalent) confirms the package exists and is actively maintained
- Problem: [what this solves]
- Existing option: [helper/component/local implementation]
- Roll-our-own complexity: low | medium | high — [why]
- Dependency value: [why the package earns its maintenance cost]
- Risk: [bundle size, maintenance, security, API churn]
```

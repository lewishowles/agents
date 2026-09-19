---
name: vue-project-stack
description: >
  Use this skill when working in a Vue project that uses the wider Lewis Howles stack. Covers the chosen tools (Vue 3 with script setup, Tailwind, Vitest, Bun, Gitflow, GitHub Pages) with the *why* for each so suggestions can flag outdated choices, plus the @lewishowles/helpers and @lewishowles/components libraries that replace common packages.
---
# Vue project stack

Stack across Vue projects. Each tool includes rationale for assessment.

## Core stack

- **Vue 3 with `<script setup>`, Composition API**
  _Why:_ smaller runtime, easier composable extraction, less boilerplate, composable reactive primitives
- **Tailwind (utility-first)**
  _Why:_ colocates styles with markup, removes class-naming overhead, fast iteration, easy audits
- **Vitest**
  _Why:_ Vite-native (no dual config), fast watcher, modern API; natural pairing for Vue 3 + Vite
- **Vue Router**
  _Why:_ standard production router for Vue SPAs; keeps navigation, params, query strings, and route metadata explicit
- **Pinia**
  _Why:_ official client-side store for Vue; simple Composition API model and strong TypeScript support
- **VueUse**
  _Why:_ proven Vue composables for browser/reactive patterns; less bespoke code
- **Bun (package manager)**
  _Why:_ fast installs, npm-compatible registry, drop-in replacement; npm/pnpm valid fallbacks
- **Gitflow branching**
  _Why:_ release/develop separation suits static-hosted deployment style
- **GitHub Pages**
  _Why:_ free static hosting, branch-based deploy, no extra infrastructure
- **Node.js (server-side) / vanilla JS (browser, VS Code extensions)**
  _Why:_ Node for tooling/scripts; vanilla JS where bundle size or runtime constraints matter

## Helpers library — `@lewishowles/helpers`

Replaces ad-hoc utilities. Check before adding dependencies. See package README for docs.

Import path: `import { getNextIndex } from "@lewishowles/helpers/array"`

Key helpers:

- Type guards: `isNonEmptyArray`, `isNonEmptyString`, `isNonEmptyObject`, `isNonEmptySlot`
- Validation: `validateOrFallback`, `validateField`
- Object access: `get`, `set`, `forget`, `deepMerge`, `pick`, `omit`, `pluck`
- Array operations: `getNextIndex`, `chunk`, `compact`, `unique`
- Strings: `StringManipulator`
- URLs: `getUrlParameter`, `updateUrlParameter`
- Vue: `runComponentMethod`

Missing helper? Propose adding to @lewishowles/helpers, don't inline or add new dependency.

## Component library — `@lewishowles/components`

Accessible component library. Use live docs at [components.howles.dev](https://components.howles.dev/) or the CLI before source files:

```sh
npx @lewishowles/components list
npx @lewishowles/components info <component>
npx @lewishowles/components snippet <component>
npx @lewishowles/components pattern
```

Missing? Propose adding to library, don't duplicate locally.

## Data layer structure

When using Pinia Colada for server data, organise by responsibility:

```
src/
├── api/          # Raw fetch functions — no keys, no cache logic
├── queries/      # Key factories, defineQueryOptions, defineQuery
└── mutations/    # defineMutation definitions
```

State management responsibilities:

| Layer             | Use for                                                                         |
| ----------------- | ------------------------------------------------------------------------------- |
| Pinia stores      | Client-owned app state, UI state, user preferences, app-wide flags              |
| Pinia Colada      | Server data — fetching, caching, revalidation                                   |
| VueUse            | Reusable reactive/browser utilities — storage, observers, media queries, timers |
| Plain composables | Project-specific local shared state that doesn't need caching                   |

## Completion

For frontend UI changes, run [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) before handoff.

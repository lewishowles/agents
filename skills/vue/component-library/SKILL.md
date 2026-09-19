---
name: component-library
description: >
  Use this skill when choosing, reusing, or wrapping components from @lewishowles/components, including sibling components inside the library. Prefer its CLI and docs before source searches.
---
# Component library

Use @lewishowles/components discovery (CLI, live docs) before source files when the component or API is unclear. Apply this when composing sibling components inside the library as well as when consuming the published package elsewhere.

## Core contract

After loading this skill, do this before searching `src/components/**` or `@lewishowles/components` source:

1. Check whether the current repo already shows the exact component and API needed.
2. If not, use the `components` CLI to inspect available components, examples, props, slots, events, and patterns.
3. Use live docs next when the CLI does not answer the question.
4. Search source only when the CLI/docs are missing, stale, incomplete, or the implementation detail itself is the task.

Skip only when current context identifies the exact component API and no sibling discovery is needed, or when the task is solely an internal implementation change.

## `@lewishowles/components`

`@lewishowles/components` publishes the `components` CLI. Use it as the cheap discovery surface when a project consumes the library and the right component or pattern is uncertain.

Preferred discovery commands:

```sh
npx @lewishowles/components list
npx @lewishowles/components info <component>
npx @lewishowles/components snippet <component>
npx @lewishowles/components pattern
```

Answer questions such as:

- What components exist for this need?
- What props, slots, events, methods, and styling hooks are available?
- What snippet examples exist for this component?
- Is there a multi-component pattern close to the requested UI?
- What does a data table, form, modal, navigation, or loading state look like without reading source files?

If CLI doesn't answer, use live docs next, then source inspection.

## Helpers library

@lewishowles/helpers has no consumer CLI. Inspect via README, exports, and imports. Don't claim a CLI exists unless package metadata shows one.

## Using the result

- Prefer existing components and documented patterns before building bespoke UI.
- Keep accessibility notes from the component docs or CLI output in the implementation.
- Use component names, prop names, slot names, and examples exactly as documented.
- If close but incomplete, propose library improvement rather than forking locally.
- Check wrapper APIs before importing lower-level components directly.

---
name: component-api-design
description: >
  Use this skill when creating a component or designing its public API — props, slots, emits, v-model, expose — or reviewing whether an existing API is consistent and discoverable.
---
# Component API design

Design public contract before internals: props, slots, emits, `v-model`, `defineExpose`.

## Before implementation

When the component shares a concern with an approved sibling or family member (a similar field type, a shared prop, a parallel emit), read that sibling's actual API first, not just the nearest visually similar component. Fill the table from that precedent; only diverge with a stated reason.

Write a compact contract table before editing component internals. Include:

| Area          | Decision                                                 |
| ------------- | -------------------------------------------------------- |
| Job           | The user-visible responsibility of the component         |
| Model         | The value shape and single/multiple states               |
| Props         | Consumer configuration and defaults                      |
| Slots         | Caller-owned content, slot names, and slot props         |
| Emits/expose  | Domain events and narrow imperative methods              |
| Copy          | Default user-facing text and translation/override points |
| Accessibility | Labels, descriptions, focus, keyboard, and errors        |
| Styling       | Root hooks, parts, states, and visual constraints        |
| Ownership     | Facts the component owns and interpretation left outside |

Use the table to resolve competing interpretations before implementation. If a decision is still material or ambiguous, present the alternatives and wait for the user before editing.

## API shape

- Start from component job, not DOM structure.
- Keep smallest API for known use cases; avoid speculative props and escape hatches.
- Prefer one clear composition path over parallel APIs.
- Name entries after domain concepts, not implementation details.
- Treat renaming or removing a prop, slot, event, model, or exposed method as breaking only after release. Before release, choose the best final API and update every in-scope caller, test, example, and document instead of preserving a weaker contract or adding a compatibility shim.
- Public option needs real outside caller. If only current wrapper can supply it, keep it internal or redesign.
- Write minimal caller example first. If example needs framework internals, it is not public API.
- Expose only facts or capabilities the component itself owns. Do not add a parent feature's vocabulary, callback, resolver, or output shape to a child merely because the parent needs its data. Let the parent interpret the smallest child contract that belongs there.

## Props

- Use props for configuration and directly rendered data.
- Prefer named props over catch-all objects unless the object is already a shared domain type.
- Keep boolean props positive and state-based: `disabled`, `loading`, `invalid`, not `notInteractive`.
- Avoid prop pairs that can drift apart; use one structured prop when values belong together.
- Do not add props for content that belongs in slots.

For prop JSDoc, metadata, and user-facing docs, describe what the prop accepts and why a user would set it, not its internal mechanism. Include one concrete example for any prop whose shape is an object, callback, or config DSL, not only when the value is otherwise unclear.

## Slots

- Use slots for caller-owned content, layout variation, rich markup, and UI text needing easy translation.
- Name slots by purpose: `header`, `actions`, `empty`, `error`, `item`.
- Provide slot props when translated or caller-owned content needs component state, such as counts, selected items, errors, or IDs.
- Keep slot props minimal. After release, keep them stable because they are part of the public API.
- Do not use a slot when a simple string prop is enough.

Require explicit `<template #name>` for named slots. For broader Vue conventions, see `vue`.

## Emits

- Use emits for user actions and meaningful state transitions.
- Name events after what happened: `submit`, `close`, `select`, `update:open`.
- Emit domain payloads, not DOM events, unless wrapping a native control intentionally.
- Keep payload shape consistent across related events.
- Do not emit internal lifecycle steps consumers cannot act on.

## v-model

- Use `v-model` when the parent owns a value and the component edits it.
- Prefer a single default model for the primary editable value.
- Use named models only for multiple independent parent-owned values.
- Pair model names with the domain concept: `v-model:open`, `v-model:selected-id`, `v-model:filters`.
- Avoid duplicating model with change event unless consumers need controlled state plus explicit action.

## defineExpose

- Expose methods only for imperative actions props/slots/events cannot express cleanly.
- Keep exposed methods narrow: `focus()`, `open()`, `close()`, `reset()`.
- Do not expose internal refs, stores, query state, or implementation helpers.
- Document why imperative exists when declarative seems plausible.

## Documenting the API

- State precedence and merge or dedup order explicitly whenever multiple sources feed the same output, such as combined error sources or an overridable default.
- For an opt-out boolean, give one concrete scenario where the non-default value is the right call.
- Document every slot's scope props in a table, even when the slot seems minor. An undocumented slot prop is an undocumented part of the API.
- Redefine a recurring cross-cutting term at each place it's used, rather than once and assumed.

## Review checklist

- Can consumers understand the API without reading internals?
- Are props, slots, emits, models, and exposed methods each used for the right responsibility?
- Is there one obvious way to complete the common workflow?
- Are names consistent with neighbouring components?
- Is compatibility work backed by a released API, rather than an earlier commit in the same unreleased work?
- Does UI text that may need translation live in slots with enough slot props?
- Does the written documentation give an example for every prop or slot shaped as an object, callback, or config DSL, and tabulate every slot's scope props?
- Does the API preserve accessibility needs: labels, descriptions, focus, and error messaging?
- For UI components, has [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) been run before handoff?
- Does every API entry describe a concept this component owns, rather than one current parent or consumer?

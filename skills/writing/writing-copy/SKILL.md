---
name: writing-copy
description: >
  Use this skill when writing or reviewing UI microcopy: labels, errors, empty states, tooltips, CTAs, form help, and confirmations. Keep the voice consistent and make controls and messages clear without visual context.
---
# UI copy

Microcopy = short interface text guiding action. Bar: clear in one read.

## Accessible phrasing

Write each control and message so its meaning survives without visual context: use specific accessible names, make inline errors work with the field label, and do not rely on colour or placeholder text alone. For the full voice and accessibility checklists, see `writing` and `accessibility`.

## Before writing

- Establish the user's goal, the product fact to communicate, the available next action, and the stakes. Ask for context when a missing detail would change the copy
- Don't invent causes, timings, outcomes, or recovery steps. State what the product knows and offer only actions it can support

## Voice and tone

- Keep product voice consistent across the flow; adapt tone to the user's situation and the consequence of the action
- For failures and frustration, be calm, direct, and recovery-focused. Don't add cheerfulness
- For high-stakes or destructive actions, state consequences plainly and make backing out easy
- For routine success, confirm the specific outcome briefly. Reserve celebration for meaningful progress

## Buttons and CTAs

- Lead with verb — `Save changes`, not `OK`
- Be specific about what happens — `Delete account` beats `Confirm`
- Match surrounding form: `Sign in` form → `Sign in` button, not `Submit`
- Icon-only buttons still need accessible name: `Close menu`, `Delete project`, `Copy link`

## Error messages

- Say what went wrong and what to do — `Password must be at least 8 characters`, not `Invalid password`
- Plain language; never expose stack traces or codes alone
- Don't blame user — `That email is already taken` not `You entered an invalid email`
- Inline errors should work with field label: `Enter an email address`, not `Email error`

## Empty states

- Acknowledge empty and point to next action — `No projects yet. Create one to get started.`
- Avoid placeholder text that looks like data — confuses screen readers and low-cognition users

## Confirmations

- Confirm with identifiable info — `User "Lewis Howles" deleted`, not `User deleted`
- Destructive actions: restate consequence — `Delete account? This removes 12 projects and can't be undone.`
- Prefer undo for reversible destructive actions. Use confirmation for hard-to-undo or high-impact actions

## Supporting text

- Place near related input; don't hide essential info in tooltips
- Keep short — more than two sentences belongs in docs

## Reviewing a flow

- Review related titles, instructions, controls, errors, and confirmations together
- Use one term for each action, object, and status unless the product distinguishes them
- Remove repetition between nearby strings while preserving the context each control or message needs on its own
- Check the sequence explains what happened, what the user can do, and what happens next
- Read each string in its rendered context, including its accessible name, nearby guidance, and resulting state

## Attribution

The context, situational-tone, and flow-review guidance adapts ideas from [content-designer/ux-writing-skill](https://github.com/content-designer/ux-writing-skill), MIT licensed.

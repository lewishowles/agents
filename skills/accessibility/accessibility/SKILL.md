---
name: accessibility
description: >
  Use this skill when editing HTML, UI components, or interface copy, even if accessibility isn't mentioned. Covers WCAG 2.2 AA, keyboard, screen readers, semantics, focus, forms, and contrast.
---
# Accessibility

WCAG AA baseline; AAA where feasible. Inaccessible = incorrect. Covers blind/low-vision, colourblind, keyboard-only, neurodivergent, and plain-language users.

WCAG criteria define outcomes, not one required implementation. Guidance labelled **Preferred technique**, **Project default**, or **Platform guidance** may name one way to meet a criterion or deliberately exceed WCAG. Do not report those items as normative conformance requirements.

Never assert a feature's browser or assistive-tech support from training memory; it ages fast. The MDN MCP server (live docs and browser-compat data) is configured but disabled by default: ask the user to enable it, then query it to confirm support before relying on it.

## Visual

- **Colour contrast (WCAG 1.4.3 and 1.4.11)**: min 4.5:1 for normal text and 3:1 for large text; meaningful UI boundaries, states, and graphical objects need 3:1 where the criteria apply. Use colorcontrast.app
- **Don't rely on colour alone (WCAG 1.4.1)**: provide another visual cue, such as text, an icon, shape, or pattern
- **Text readability**: line-height ~1.5, line length ~65 chars, readable font sizes
- **Responsive design (WCAG 1.4.10)**: reflows at 320 CSS px or 400% zoom without losing content or functionality; allow two-dimensional scrolling where the content requires it, such as data tables. **Project default**: keep it navigable below 250px wide where practical
- **Robust text layout**: set `min-width: 0` in flex/grid children with long text; choose wrapping, truncation, or scrolling deliberately
- **Images**: set dimensions or aspect ratio so layout does not jump. Lazy-load below-fold images

## Content & copy

- **Clear language**: no jargon; assume zero context. Provide hints and links
- **Descriptive links & buttons**: link text explains action alone. Not "Delete" — "Delete user Lewis Howles". Not "Learn more" — "Visit MDN docs for the `button` tag"
- **Confirmation & reassurance**: show chosen option (e.g. plan name). Success messages use identifiable info: "User 'Lewis Howles' successfully deleted", not generic text
- **Vue components**: prefer `@lewishowles/components`. Follow the Vue skill and check live component docs

## Documentation

- Treat accessibility fixes as bug fixes, not features
- Document accessibility only when a user-facing workflow, API, configuration, or support need changes. Internal accessibility mechanics need no README note.

## Structure & semantics

- **Preferred technique — heading hierarchy**: nest headings logically and avoid forward rank skips where possible. Use the correct level; change appearance if needed. Looks like a heading → make it a heading
- **Landmark regions**: use `main`, `article`, `aside`, `nav`
- **DOM order matches visual order**: tab order should match screen layout. Focus must not jump backwards

## Images & media

- **Alt text**: describes image, not "image of". Decorative: `<img alt="" />`
- **Complex images (charts)**: provide a definition-list legend or narrative findings
- **Video & audio**: captions/transcripts
- **No autoplay**: respects data/battery and gives control

## Interaction

- **Keyboard access**: every action works by keyboard. For drag-drop, provide button alternative. Focusable selectors: see code-style
- **Visible focus**: show keyboard focus with ring indicator; never remove outline. After delete, move focus sensibly (next row, not page top)
- **Focus after errors**: after failed form submission, move focus to the error summary or first invalid field
- **Preferred technique — bypass repeated blocks**: use a skip link such as `<a href="#main">Skip to main content</a>` with `<main id="main" tabindex="-1">`, or another valid mechanism such as headings or landmarks
- **Project default — motion**: respect `prefers-reduced-motion`. Guard animations: `@media (prefers-reduced-motion: reduce) { ... }`. This also supports WCAG 2.3.3 AAA where interaction-triggered motion is non-essential
- **Transitions**: avoid `transition: all`; animate explicit properties with reduced-motion fallbacks
- **Project default — timing**: messages do not auto-dismiss. WCAG 2.2.1 permits time limits when users can turn them off, adjust them, extend them, or an exception applies
- **Project default — touch targets**: aim for 44×44px. The WCAG 2.5.8 AA floor is 24×24 CSS px, with spacing and other exceptions
- **Modal pattern**: modal dialogs contain their tab sequence. On open, save `document.activeElement` and move focus into the dialog; on close, restore focus to the trigger or the next logical element. Follow the APG modal dialog pattern
- **Keyboard contract for interactive widgets** (dropdowns, menus, tabs, comboboxes): Arrow keys navigate; Enter or Space activates; Escape cancels/closes. Match [ARIA authoring practices](https://www.w3.org/WAI/ARIA/apg/patterns/)
- **Dialog ARIA**: `role="dialog"` + `aria-modal="true"` + `aria-labelledby` pointing at dialog heading

## Forms & inputs

- **Label association**: `<label for="inputId">` → `<input id="inputId">`, or wrap. Never placeholder alone
- **Input type and mode**: use most specific `type`, `inputmode`, and `autocomplete` for expected data
- **Grouped inputs**: `<fieldset>` + `<legend>` for radio, checkboxes, related fields
- **Preferred technique — help text & instructions**: `aria-describedby="helpId"` pointing at `<span id="helpId">`
- **Preferred technique — validation & errors**: `aria-invalid="true"` + `aria-errormessage="errorId"` pointing at error text. For multi-error forms, add an error summary linked to fields
- **Autocomplete attributes**: `autocomplete="email"`, `autocomplete="password"`, `autocomplete="current-password"` — helps password managers, reduces friction
- **Error recovery**: don't clear form on error. Let user fix and resubmit

```html
<label for="email">Email address</label>
<input
  id="email"
  type="email"
  autocomplete="email"
  aria-describedby="email-help email-error"
  aria-invalid="true"
  aria-errormessage="email-error"
/>
<p id="email-help">Use the email address for your account.</p>
<p id="email-error">Enter an email address, like name@example.com.</p>
```

```html
<section role="dialog" aria-modal="true" aria-labelledby="delete-title">
  <h2 id="delete-title">Delete project?</h2>
  <p>This removes "Website refresh" and can't be undone.</p>
  <button type="button">Cancel</button>
  <button type="button">Delete project</button>
</section>
```

## Dynamic content & updates

- **Status messages (WCAG 4.1.3)**: make outcomes, application state, progress, and errors programmatically determinable without moving focus. Use the semantic element or role that matches the message, such as `<output>`, `role="status"`, `role="alert"`, `role="log"`, or `aria-live`
- **Preferred technique — live regions**: use `aria-live="polite"` for non-urgent messages and `assertive` only when interruption is necessary. Add a label only when it gives the region useful context
- **Screenreader-only content**: `.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(1px, 1px, 1px, 1px); }` — hidden visually, announced to assistive tech

## Controls

- Icon-only buttons need an accessible name via visible text, `aria-label`, or `aria-labelledby`
- Use `aria-label` and `aria-labelledby` only when the element's implicit or explicit role supports an author-provided name. Prefer visible or visually hidden text, and don't add ARIA names to paragraphs, generic spans/divs, or presentational content
- Do not put click handlers on non-interactive elements when button/link is correct semantic control
- Do not block paste in form fields
- Destructive actions need confirmation, undo, or both
- **Accessible names built from multiple pieces of state** (tree nodes, list rows, grid cells): put the most important disambiguating information first, not last — a screen reader user often stops listening once they've heard enough to act. Don't rely on visual position or component configuration to convey what the label prioritises in speech

## Semantics & structure (expanded)

- **Tables**: `<table>` + `<caption>`, `<thead>` + `<th scope="col">`, `<th scope="row">`
- **Lists**: `<ul>` unordered, `<ol>` ordered, `<dl>` definition lists. No div/paragraph fake lists
- **Abbreviations**: `<abbr title="full text">` for acronyms
- **Language tag**: `lang="en"` on `<html>`. Use `lang="cy"` or `lang="fr"` where content switches
- **Navigation & landmarks**: use `<nav>`, `<main>`, `<aside>`, `<article>`

## Quick-reference checklist

PR-pasteable checklist: [`references/checklist.md`](references/checklist.md).

## Before handoff

Review changed UI against [`references/checklist.md`](references/checklist.md), fix issues found, and state which checks were actually performed. Report WCAG outcomes separately from preferred techniques and project or platform defaults. Passing the checklist or an automated scan does not prove WCAG conformance; manual and assistive-technology testing may still be needed.

## Content warnings & safety

- **Flashing & strobing**: max 3 flashes/second in any 1-second window. Test GIFs, videos, carousels
- **Content warnings**: flag violence, self-harm, abuse, graphic medical, trauma triggers before user encounters. Give visibility control

## Attribution

The distinction between normative WCAG requirements and house rules adapts the compliance-profile model from [fecarrico/A11Y.md](https://github.com/fecarrico/A11Y.md), MIT licensed.

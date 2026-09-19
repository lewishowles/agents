# WCAG 2.2 AA checklist

Use this working checklist during a full client audit, alongside the normative WCAG 2.2 standard. It is not exhaustive and does not establish conformance by itself. Each section checks outcomes associated with the named criteria; implementation examples are common techniques, not the only conforming methods. Project and platform defaults are separated at the end.

---

## Perceivable

### 1.1 Text alternatives

- [ ] All meaningful images have descriptive alt text
- [ ] Decorative images have `alt=""`
- [ ] Complex images (charts, diagrams) have an equivalent description or data representation
- [ ] Icon-only buttons have accessible names

### 1.2 Time-based media

- [ ] Audio-only content has a text transcript
- [ ] Video has synchronised captions (accurate, complete, with speaker IDs)
- [ ] Video has audio description for visual-only content

### 1.3 Adaptable

- [ ] Heading hierarchy represents the content structure; forward rank skips are avoided where possible
- [ ] Lists use `<ul>`, `<ol>`, `<dl>` — not fake lists with paragraphs/divs
- [ ] Table headers, relationships, and an accessible name or description are programmatically determinable
- [ ] Form inputs have associated `<label>` elements (not placeholder-only)
- [ ] Landmark regions present (`<main>`, `<nav>`, `<aside>`, `<header>`)
- [ ] Reading order in DOM matches visual order
- [ ] Instructions don't rely on shape, colour, or position alone

### 1.4 Distinguishable

- [ ] Text contrast ≥ 4.5:1 (normal) / 3:1 (large text, 18pt+ or 14pt bold+)
- [ ] Meaningful UI boundaries, states, focus indicators, and graphical objects meet 3:1 where SC 1.4.11 applies
- [ ] Colour is not the only way to convey information
- [ ] Text resizes to 200% without loss of content or functionality
- [ ] Content reflows at 400% zoom / 320 CSS px without loss; two-dimensional scrolling remains only where an exception applies
- [ ] Background audio that plays for more than 3 seconds can be paused, stopped, or controlled independently

---

## Operable

### 2.1 Keyboard accessible

- [ ] Every interactive element is reachable and operable via keyboard
- [ ] Keyboard focus can leave each component using a standard or documented method
- [ ] Keyboard shortcuts don't conflict with AT shortcuts; can be remapped or disabled

### 2.2 Enough time

- [ ] Content time limits can be turned off, adjusted, or extended unless a WCAG exception applies
- [ ] No moving/blinking content that can't be paused after 5 seconds

### 2.3 Seizures & physical reactions

- [ ] Nothing flashes more than 3 times per second

### 2.4 Navigable

- [ ] Repeated blocks have a bypass mechanism, such as a skip link, headings, or landmarks
- [ ] Each page has a descriptive `<title>`
- [ ] Focus indicator visible at all times (no `outline: none` without replacement)
- [ ] Focus order is logical — tab sequence matches visual/reading order
- [ ] Focus after errors moves to an error summary or invalid field when that is the clearest recovery path
- [ ] Modal dialogs follow the APG focus pattern: focus moves inside, the tab sequence stays contained, and focus returns to the trigger or next logical element
- [ ] Heading structure allows users to understand and navigate the page
- [ ] Link text is descriptive in context (not "click here" or "learn more")

### 2.5 Input modalities

- [ ] Pointer targets meet the 24×24 CSS px WCAG floor or a spacing, equivalent-control, inline, user-agent, or essential exception
- [ ] No drag-only interactions — a button alternative exists

---

## Understandable

### 3.1 Readable

- [ ] `<html lang="en">` set; inline `lang` attributes on blocks in other languages

### 3.2 Predictable

- [ ] Navigation is consistent across pages
- [ ] Components with the same function have consistent labels
- [ ] No unexpected context changes on focus or input (no auto-submit on select)

### 3.3 Input assistance

- [ ] Error messages identify the field and describe the issue
- [ ] Invalid inputs are programmatically identified and associated with their error text; `aria-invalid` and `aria-errormessage` are preferred where supported
- [ ] Multi-error forms provide an error summary linked to each invalid field where that improves recovery
- [ ] Required fields indicated (not colour-only)
- [ ] `autocomplete` attributes set for personal data fields
- [ ] Submissions with legal, financial, or data consequences can be checked, reversed, or confirmed

---

## Robust

### 4.1 Compatible

- [ ] HTML is structurally valid enough for roles, states, properties, and relationships to be programmatically determined
- [ ] ARIA roles, states, and properties are used correctly
- [ ] Custom interactive widgets follow the applicable ARIA Authoring Practices pattern
- [ ] Modal dialogs expose the applicable dialog semantics and behave as modal for every user
- [ ] Status messages are programmatically determinable without receiving focus; suitable techniques include `<output>`, status roles, alerts, logs, and live regions

---

## Project and platform defaults

- [ ] Messages do not auto-dismiss
- [ ] Form values remain available after a submission error
- [ ] Form fields do not block paste
- [ ] Non-essential motion respects `prefers-reduced-motion`; this also supports WCAG 2.3.3 AAA
- [ ] Touch targets meet platform guidance: 44×44pt on iOS and 48×48dp on Android
- [ ] Custom components are tested with the assistive-technology and browser combinations agreed in the audit scope

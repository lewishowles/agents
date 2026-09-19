# Accessibility implementation checklist

Quick reference for changed UI. It combines WCAG 2.2 A/AA outcomes, preferred techniques, and stricter project or platform defaults. The label on each item identifies which contract it represents. Paste it into a PR description or use it as a review gate. For criterion-by-criterion audit work, use the accessibility-audit skill.

## Visual

- [ ] **WCAG 1.4.3 / 1.4.11:** Colour contrast ≥ 4.5:1 for normal text and ≥ 3:1 for large text and meaningful UI boundaries, states, and graphical objects where the criteria apply
- [ ] **WCAG 1.4.1:** Colour is not the only visual means of conveying information
- [ ] **WCAG 1.4.10:** Content reflows at 320 CSS px or 400% zoom without loss; two-dimensional scrolling remains only where content requires it
- [ ] **Project default:** No content is lost or overlaps below 320px wide

## Structure and semantics

- [ ] **Preferred technique:** Heading hierarchy is logical and avoids forward rank skips where possible
- [ ] **Preferred technique:** Landmark regions use `<main>`, `<nav>`, `<aside>`, and `<article>` where they match the content
- [ ] **Preferred technique:** Lists use `<ul>`, `<ol>`, or `<dl>` rather than visually styled generic elements
- [ ] **Preferred technique:** Data-table relationships use appropriate captions, headers, and scopes
- [ ] **WCAG 3.1.1:** The page language is programmatically identified

## Keyboard and focus

- [ ] **WCAG 2.1.1:** Every action is operable by keyboard
- [ ] **WCAG 2.4.3:** Focus order preserves meaning and operability
- [ ] **WCAG 2.4.7:** Keyboard focus is visible
- [ ] **APG modal pattern:** Modal tab order stays inside the dialog; focus moves inside on open and returns to the trigger or next logical element on close
- [ ] **Preferred technique for WCAG 2.4.1:** Repeated blocks have a bypass mechanism, such as a skip link, headings, or landmarks
- [ ] **APG widget pattern:** Keyboard interaction matches the selected widget pattern

## Forms

- [ ] **WCAG 1.3.1 / 3.3.2:** Every input has a programmatically associated label or instruction; placeholder text is not the sole label
- [ ] **Preferred technique:** Related inputs use `<fieldset>` + `<legend>`
- [ ] **Preferred technique:** Invalid inputs use `aria-invalid` and associate their error text
- [ ] **Preferred technique:** Help text is associated with `aria-describedby`
- [ ] **Project default:** Form values remain available after a submission error

## Images and media

- [ ] **WCAG 1.1.1:** Informative images have equivalent text alternatives
- [ ] **WCAG 1.1.1:** Decorative images are ignored by assistive technologies
- [ ] **WCAG 1.1.1:** Complex images have an equivalent description or data representation
- [ ] **WCAG 1.2:** Prerecorded video has captions and audio-only content has an equivalent alternative
- [ ] **Project default:** Media does not autoplay

## Dynamic content

- [ ] **WCAG 4.1.3:** Status messages are programmatically determinable without receiving focus; use suitable semantics such as `<output>`, `role="status"`, `role="alert"`, `role="log"`, or `aria-live`
- [ ] **Project default:** Messages do not auto-dismiss
- [ ] **WCAG 4.1.2:** Icon-only buttons have an accessible name; visible or visually hidden text is preferred

## Motion

- [ ] **Project default / WCAG 2.3.3 AAA:** Non-essential interaction-triggered motion respects `prefers-reduced-motion: reduce`
- [ ] **WCAG 2.3.1:** Flashing content remains below the permitted threshold

## Touch and mobile

- [ ] **Platform guidance:** Touch targets are at least 44 × 44pt on iOS and 48 × 48dp on Android
- [ ] **WCAG 1.4.4:** The viewport does not disable zoom (`user-scalable=no` is absent)

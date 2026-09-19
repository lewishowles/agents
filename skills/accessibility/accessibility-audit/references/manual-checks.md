# Manual verification: what an agent can and can't do

Automated scanners cover only machine-detectable accessibility issues. Manual verification is still required. If browser tool access is available (Claude's built-in browser tools, or a browser MCP server such as Safari Technology Preview's), an agent can directly perform many of these checks instead of only asking the user to do them by hand. Genuine screen-reader and assistive-technology testing always needs a human — no current browser MCP drives VoiceOver, NVDA, or JAWS; they expose DOM/accessibility-tree inspection, screenshots, and scripted interaction, not AT output.

Labels, ARIA, and contrast are called out as agent-checkable in the [WebKit blog announcement of the Safari MCP server](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/): "the Safari MCP server lets your agent check for common accessibility issues like missing labels, improper ARIA attributes, and poor contrast." That's the same generic DOM/JS/screenshot access as any other browser MCP, not a dedicated accessibility tool — which is why those checks are tagged **Agent** below rather than treated as unique to one MCP implementation.

Tag meanings:

- **Agent** — an agent with browser tools can check this directly and reliably
- **Partial** — an agent can surface signal, but a human must judge quality/context
- **Human** — needs a human, real assistive technology, or a real device; no browser tool substitutes

## Perceivable

| Check                                         | Who     | Method                                                                             |
| --------------------------------------------- | ------- | ---------------------------------------------------------------------------------- |
| Alt text present on images                    | Agent   | Read DOM/accessibility tree for `alt` attributes                                   |
| Alt text is meaningful (not just present)     | Partial | Agent lists the text; human judges whether it actually describes the image         |
| Decorative images have `alt=""`               | Agent   | DOM check                                                                          |
| Complex image has long description/data table | Partial | Agent confirms an associated description element exists; human judges completeness |
| Captions/audio description on video           | Human   | Requires watching/listening to the media                                           |
| Heading hierarchy logical                     | Agent   | Read accessibility tree, check heading levels in order                             |
| Lists/tables use correct semantic elements    | Agent   | DOM inspection                                                                     |
| Form inputs have associated labels            | Agent   | DOM inspection (`<label for>`, `aria-label`, `aria-labelledby`)                    |
| Landmark regions present                      | Agent   | Accessibility tree inspection                                                      |
| DOM/reading order matches visual order        | Partial | Agent compares tab/DOM order against a screenshot; human confirms edge cases       |
| Colour contrast ratios                        | Agent   | Evaluate computed `color`/`background-color` in-page and calculate the ratio       |
| Reflow at 400% zoom / 320px width             | Agent   | Resize viewport, screenshot, check for lost content or horizontal scroll           |
| Background audio can be paused                | Human   | Requires listening and interacting with real audio controls                        |

## Operable

| Check                                            | Who     | Method                                                                                      |
| ------------------------------------------------ | ------- | ------------------------------------------------------------------------------------------- |
| Every interactive element reachable by keyboard  | Agent   | Simulate repeated Tab presses, confirm each control receives focus                          |
| No keyboard traps                                | Agent   | Tab forward through the whole page and Shift+Tab back; confirm it returns, doesn't stick    |
| Auto-dismissing messages / timing                | Partial | Agent screenshots over time to see if content vanishes unprompted; human confirms intent    |
| Flashing content ≤ 3/second                      | Partial | Agent can frame-diff a recording for rough flash rate; precise measurement needs a human    |
| Skip link present and functional                 | Agent   | Click/activate it, confirm focus and scroll move to main content                            |
| Page title descriptive                           | Agent   | Read page title                                                                             |
| Focus indicator visible                          | Agent   | Screenshot after moving focus, confirm a visible ring/outline exists                        |
| Focus order logical                              | Agent   | Compare the Tab sequence to the visual layout                                               |
| Focus moves to error summary after failed submit | Agent   | Trigger the error state, read the active element                                            |
| Modal traps focus, restores on close             | Agent   | Open modal, Tab through to confirm it wraps inside; close, confirm focus returns to trigger |
| Link/button text descriptive in context          | Partial | Agent lists all link/button text; human judges clarity out of context                       |
| Touch targets ≥ 44×44 / 48×48                    | Agent   | Measure element bounding boxes via script                                                   |
| No drag-only interactions                        | Partial | Agent confirms a button/keyboard alternative exists; human confirms it's usable             |
| Paste not blocked in fields                      | Agent   | Simulate a paste event, confirm the field value updates                                     |

## Understandable

| Check                                        | Who     | Method                                                                     |
| -------------------------------------------- | ------- | -------------------------------------------------------------------------- |
| `lang` attribute set                         | Agent   | DOM inspection                                                             |
| Navigation/labels consistent across pages    | Partial | Agent compares markup across pages; human judges consistency of meaning    |
| No unexpected context change on focus/input  | Agent   | Interact with focus/input, watch for unrequested navigation or submission  |
| Error messages identify field and issue      | Agent   | Trigger validation, read the associated error text                         |
| `aria-invalid` / `aria-errormessage` present | Agent   | DOM inspection                                                             |
| Required fields indicated (not colour-only)  | Partial | Agent checks for text/icon markers; human confirms they're not colour-only |
| `autocomplete` attributes set                | Agent   | DOM inspection                                                             |
| Form not cleared on error                    | Agent   | Submit invalid data, confirm values are retained                           |

## Robust

| Check                                                                     | Who     | Method                                                                         |
| ------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------ |
| Valid HTML (no duplicate IDs, unclosed elements)                          | Agent   | Script a check across the DOM, or run a validator                              |
| ARIA roles/states/properties present and structurally sound               | Partial | Agent checks presence and structure; human confirms they match the APG pattern |
| Widgets follow ARIA keyboard contract                                     | Agent   | Simulate Arrow/Enter/Space/Escape, confirm expected behaviour                  |
| Dialog roles correct (`role="dialog"` + `aria-modal` + `aria-labelledby`) | Agent   | DOM inspection                                                                 |
| `aria-live` regions present where needed                                  | Agent   | DOM inspection — presence only                                                 |
| `aria-live` regions actually announce to a screen reader                  | Human   | No browser MCP drives real AT output; needs VoiceOver/NVDA/JAWS                |
| Full screen reader pass (VoiceOver, NVDA, JAWS)                           | Human   | See [screen-reader-testing.md](screen-reader-testing.md) — always manual       |

## Component states

Unlike most checks above, these depend on whether the app exposes a way to reach the state at all. There's no dedicated tool that reliably forces a real app's loading/empty/error states the way a Storybook harness or mocked test environment would: an agent working against a live product has to find or ask for the seam.

| Check                                   | Who     | Method                                                                                                                                                     |
| --------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Loading state reachable and inspectable | Partial | Throttle the network (browser MCP network conditions, if supported) or ask the user for a seam (query param, delay flag); if none exists, don't guess, ask |
| Empty state reachable and inspectable   | Partial | Look for a seeded empty account/dataset or a way to clear data; often needs the user to point at one                                                       |
| Error state reachable and inspectable   | Agent   | Submitting invalid data or disconnecting the network usually surfaces this directly                                                                        |
| Error state announced (not colour-only) | Agent   | Once the error state is reached, check for `aria-live`, icon, or text markers, same method as other error-announcement checks above                        |

## Using this during an audit

1. Run every **Agent** check directly if browser tools are available; report pass/fail with evidence (screenshot, DOM snippet).
2. Run every **Partial** check, but flag the result as needing human confirmation rather than a final pass/fail.
3. List every **Human** check as an open item for the user or a real device/AT session — don't guess at these.

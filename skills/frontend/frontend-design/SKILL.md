---
name: frontend-design
description: >
  Use this skill before public-facing UI where visual quality or brand distinctiveness matters. Covers typography, colour, motion, and composition. Distinct from accessibility and web-performance.
---
# Frontend design

Before UI code, establish design direction. Aesthetic decisions are cheap upfront; mismatched typography and colour are expensive after implementation.

Never assert a CSS or web-platform feature's browser support or Baseline status from training memory; it ages fast. The MDN MCP server (live docs and browser-compat data) is configured but disabled by default: ask the user to enable it, then query it to confirm support before relying on it.

## Decision sequence

Work through in order. If an answer is missing, ask; don't guess.

1. **Purpose** — what must this page or component achieve? (inform, convert, demonstrate, delight)
2. **Tone** — what feeling should it produce? (confident, calm, playful, minimal, authoritative)
3. **Constraints** — existing brand tokens, design system, target platform, viewport range, motion preferences
4. **Differentiation** — what makes this distinct from the generic version?
5. **Code** — only then, reach for the editor

An established product, platform, or design system takes precedence over this skill's taste defaults. Reuse its components, tokens, typography, palette, layout, and interaction patterns unless the user requests a new direction or project evidence shows that a choice is accidental or stale. A common style is not wrong merely because it is common.

For greenfield or explicitly brand-defining work, if (4) is "nothing yet", resolve it before proceeding. An existing product can choose consistency as the correct outcome; a new visual direction needs a reason.

## Typography

Choose type that reflects tone, not type that avoids controversy.

- **For greenfield work, question familiar default pairings**: Inter + anything or Roboto + anything can signal that no product-specific choice was made
- Pick scale intentionally: modular ratio (1.25, 1.333, 1.5)
- Limit to two typefaces: one for display/headings, one for body. Use weight and size before a third face
- Line height: 1.4–1.6 for body, 1.1–1.2 for large display headings
- Measure (line length): 60–75 characters for body, unconstrained for short display

## Colour

Colour should carry meaning, not just decoration.

- Start from purpose: medical dashboard needs restraint; food brand can be saturated
- Establish a palette: one dominant hue, one accent (used sparingly), neutral surface tones
- **Contrast is non-negotiable**: 4.5:1 body text, 3:1 large text and UI (WCAG AA). Check light and dark variants
- For a greenfield palette, question purple-blue or teal-green gradients unless the product gives them a clear reason
- If using a gradient, ensure clear directional rationale (light source, brand direction)

## Motion and animation

Motion should reinforce meaning, not demonstrate capability.

- Define motion vocabulary before animating: what enters, leaves, transitions?
- Prefer `transform` and `opacity`; avoid layout properties (`width`, `height`, `padding`, `top`/`left`)
- Duration: micro-interactions 100–150ms; component transitions 200–350ms; page-level 400–500ms
- Easing: ease-out for entrance (fast start, gentle stop); ease-in for exit; ease-in-out for reversible
- Always provide `prefers-reduced-motion` fallbacks: remove or replace animations, don't just slow them

## Layout and composition

- Establish grid before placing elements. 8pt grid (or 4pt for dense UIs) enforces rhythm
- Use whitespace as design, not just padding to fill
- Hierarchy should read in 3 seconds: primary, secondary, tertiary?
- Avoid symmetrical layouts by default: asymmetry creates tension; symmetry signals formality. Choose deliberately
- For heroes: lead with specific claim, not generic value prop. "Build accessible Vue components in minutes" beats "The modern component library"

## Greenfield anti-pattern prompts

Use these only when the product has no established visual owner or the user asks for a new direction. They are prompts to check whether a choice is deliberate, not reasons to override an existing brand, platform, or design system.

| Pattern to question                    | Risk                                                 | Instead                                                                         |
| -------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------- |
| Inter as default body font             | Ubiquitous; signals no decision was made             | Outfit, DM Sans, Fraunces, Syne, or a system stack used deliberately            |
| Purple-to-blue gradient hero           | Most common SaaS pattern of the last five years      | Derive colour from purpose; one strong hue beats a gradient                     |
| Card grid on white background          | Looks like a template                                | Vary density, use full-bleed sections, break the grid intentionally             |
| `transition: all`                      | Animates layout properties and causes jank           | Animate explicit properties: `transform 200ms ease-out, opacity 200ms ease-out` |
| Placeholder copy ("Lorem ipsum")       | Obscures whether layout works for real content       | Use real or realistic content from the start                                    |
| "Flat" icons with no weight system     | Inconsistent visual density across UI                | Pick one icon set; use consistent stroke width and optical size                 |
| Centred body text beyond short tagline | Hard to read; signals "I saw this on a landing page" | Left-align body copy; centre sparingly for display-sized single lines           |

## Completion gate

Before handing off to implementation, confirm:

- Typography scale and typefaces documented (or using existing tokens)
- Colour palette defined with contrast ratios checked
- Motion vocabulary described (or "no animation")
- Design reviewed at narrowest and widest breakpoints
- Checked against accessibility skill: keyboard access, focus, colour contrast, reduced-motion

---

_Adapted from the Anthropic Claude Code frontend-design skill (MIT). Reworded and extended._

The visual-owner precedence adapts ideas from Benjamin Stelzer's `scoville-ui-anti-ai-slop` skill, MIT licensed.

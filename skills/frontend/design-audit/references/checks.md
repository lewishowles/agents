# Design checks by evidence

Apply the rules in [frontend-design](../../frontend-design/SKILL.md) in the product's existing visual language. A check passes only when the named evidence shows it. Work down the tiers using the evidence supplied; record each unavailable check as **Not verified** with the missing evidence named.

## Static screenshot

A screenshot shows one viewport, theme, and state. Compare only what is visible there.

| Check | Frontend-design rule | What to look for |
| --- | --- | --- |
| Surface edges | Surfaces: border for structure, shadow for elevation | Borders explain boundaries; shadows make raised elements read as raised. |
| Nested corners | Surfaces: concentric border radius | Closely nested rounded surfaces have an even visible gap around their corners. |
| Image edges | Surfaces: low-opacity image outline | A non-interactive image remains distinct where its edge blends into the background. |
| Icon and text alignment | Surfaces: optical alignment | An icon and label look centred together at the rendered size; uneven glyphs do not pull the control off balance. |
| Text wrapping | Typography: `text-wrap: balance` and `text-wrap: pretty` | Short headings and short body copy avoid an awkward isolated final word where wrapping is visible. |
| Changing figures | Typography: tabular numbers | If a series of figures is shown, their digits align consistently; a single still cannot prove that a live number does not shift. |
| Icon weight | Iconography: stroke weight | Icon strokes have visual weight consistent with adjacent text. |

## Rendered page and captured states

This tier needs screenshots or a rendered report that shows the relevant states. A single default-state image does not cover them.

| Check | Frontend-design rule | Evidence needed |
| --- | --- | --- |
| Hover and press appearance | Iconography: `currentColor` states; Motion and animation: press scale floor | Captured hover and pressed states show the intended colour and a press size that preserves the control's visual presence. Confirm the numeric scale in source if the image alone cannot establish it. |
| Light and dark surfaces | Surfaces: layered light shadow and single-ring dark variant | Both themes show clear edges without a heavy dark shadow. |
| Interaction and alignment | Surfaces: optical alignment; Motion and animation: static state cue | In captured hover and pressed states, each control's icon and label stay optically centred, and each changed state keeps a visible static cue, such as a checkmark, a changed label, or a border. |
| State collisions | Layout and composition: establish a grid and clear hierarchy | Captured menus, panels, and feedback remain visually distinct from neighbouring content in the states shown. |
| RTL icon spacing | Surfaces: optical alignment | A captured RTL state keeps icon-and-label buttons balanced, with the smaller padding still on the icon side after the layout mirrors. |
| Number changes | Typography: tabular numbers | A sequence of rendered values shows whether digit changes shift adjacent content. |

## Source

Read only the source governing the reviewed element. Source can establish construction, even when rendered evidence is unavailable.

| Check | Frontend-design rule | Evidence needed |
| --- | --- | --- |
| Surface tokens | Surfaces: theme-specific surface colours and opacity tokens; concentric border radius | Light and dark surface treatments use project tokens; closely nested radii follow the inner radius plus padding where the surfaces read as one group. |
| Image outline | Surfaces: low-opacity inset outline | The outline uses black in light mode and white in dark mode with token-supplied opacity, separate from focus styling. |
| Text wrapping and figures | Typography: `text-wrap` and tabular numbers | The relevant heading, short body text, or changing figure uses the named property where appropriate. |
| Icon asset and states | Iconography: one `currentColor` SVG per icon | State colours come from the control's tokens rather than separate recoloured assets; stroke weight is consistent with nearby text. |
| Interactive motion construction | Motion and animation: transitions for reversible state, keyframes for one-shot sequence; Greenfield anti-pattern prompts: `transition: all` | Hover, toggle, and open states can reverse through transitions; one-shot sequences use keyframes; transitions name properties rather than `all`. |
| Press scale | Motion and animation: scale on press no smaller than `0.95` | A scale-based press effect stays at `0.95` or larger and transitions back on release. |
| State without motion | Motion and animation: visible static cue | A changed label, border, icon, or other cue communicates each state even when animation is absent. Accessibility testing of reduced-motion behaviour belongs to `accessibility-audit`. |
| Reduced-motion fallback | Motion and animation: provide a `prefers-reduced-motion` fallback | Locate the fallback in source and pass its behaviour to `accessibility-audit` for assessment; this design audit does not claim an accessibility pass. |

## Recording

Inspect the actual action sequence. Cite the relevant moment or time span; do not infer motion that the recording does not show.

| Check | Frontend-design rule | What to observe |
| --- | --- | --- |
| Interruptible response | Motion and animation: transitions for interactive states | A hover, toggle, or open state reverses smoothly when interrupted rather than jumping or restarting a fixed sequence. |
| Entrance and exit | Motion and animation: exits quieter than entrances | The exit uses less movement and feels shorter than the entrance when an exit is useful. |
| Stagger | Motion and animation: stagger only for infrequent hierarchy-setting entrances | A small group enters in a meaningful order; repeated controls and routine state changes respond together. |
| Motion restraint | Motion and animation: brief feedback and static cue | Frequent actions respond promptly, and the state remains clear in a still frame. |

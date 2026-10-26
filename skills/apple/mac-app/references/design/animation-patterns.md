# Animation patterns

## Parts

- [Animation basics](animation-patterns-core-animations.md) (upstream `core-animations.md`)
- [Phase and keyframe animators](animation-patterns-phase-keyframe-animators.md) (upstream `phase-keyframe-animators.md`)
- [Symbol effects](animation-patterns-symbol-effects.md) (upstream `symbol-effects.md`)
- [Transitions](animation-patterns-transitions.md) (upstream `transitions.md`)
- [Visual effects](animation-patterns-visual-effects.md) (upstream `visual-effects.md`)

<a id="source-design-animation-patterns-skill-md"></a>
## Source: `design/animation-patterns/SKILL.md`

# Animation Patterns

Correct API shapes and patterns for SwiftUI animations. Prevents common mistakes with spring parameter generations and PhaseAnimator/KeyframeAnimator closure signatures.

## When This Skill Activates

Use this skill when the user:
- Asks to add, fix, or review **animation** code
- Mentions **spring**, **bounce**, or **snappy** animations
- Wants **view transitions** (insertion/removal, hero)
- Asks about **PhaseAnimator** or **KeyframeAnimator**
- Wants **SF Symbol effects** (bounce, pulse, wiggle, breathe)
- Mentions **matchedGeometryEffect**
- Asks about **reduce motion** / animation accessibility
- Wants to sequence or chain animations
- Mentions **withAnimation**, **animation completions**, or **Transaction**
- Wants **scroll-driven effects** (parallax, carousels, `scrollTransition`, `visualEffect`)
- Mentions **MeshGradient**, **TextRenderer**, or **Metal shader effects** (`colorEffect`, `distortionEffect`, `layerEffect`)

## Decision Tree

Choose the right reference file based on what the user needs:

```
What are you animating?
│
├─ A state change (opacity, position, color)
│  └─ → animation-patterns-core-animations.md
│     ├─ withAnimation { } — explicit animation
│     ├─ .animation(_:value:) — implicit animation
│     └─ Spring configuration — .spring, .bouncy, .snappy, .smooth
│
├─ A multi-step / sequenced animation
│  └─ → animation-patterns-phase-keyframe-animators.md (PhaseAnimator)
│     └─ Cycles through discrete phases automatically or on trigger
│
├─ A complex multi-property animation (scale + rotation + offset)
│  └─ → animation-patterns-phase-keyframe-animators.md (KeyframeAnimator)
│     └─ Timeline-based keyframes with per-property tracks
│
├─ A view appearing / disappearing
│  └─ → animation-patterns-transitions.md
│     ├─ .transition() — insertion/removal
│     ├─ .contentTransition() — text/symbol changes
│     └─ .asymmetric() — different in/out
│
├─ A hero transition within one view hierarchy
│  └─ → animation-patterns-transitions.md (matchedGeometryEffect)
│     └─ iOS 14+: matchedGeometryEffect (NOT for NavigationStack)
│
├─ An SF Symbol animation
│  └─ → animation-patterns-symbol-effects.md
│     └─ .symbolEffect(.bounce), .pulse, .wiggle, .breathe, .rotate
│
├─ A scroll-driven, geometry-driven, or shader effect
│  └─ → animation-patterns-visual-effects.md
│     ├─ .scrollTransition — carousel scale/parallax/caption fades
│     ├─ .visualEffect — position-based effects without GeometryReader
│     ├─ MeshGradient — animatable multi-point gradients
│     ├─ TextRenderer — per-line / per-glyph text animation
│     └─ ShaderLibrary + .colorEffect / .distortionEffect / .layerEffect
│
└─ Spring physics / timing configuration
   └─ → animation-patterns-core-animations.md (Spring Configurations section)
```

## API Availability

| API | Minimum Version | Reference |
|-----|----------------|-----------|
| `withAnimation` | iOS 13 | animation-patterns-core-animations.md |
| `.animation(_:value:)` | iOS 13 | animation-patterns-core-animations.md |
| `.spring(response:dampingFraction:)` | iOS 13 | animation-patterns-core-animations.md |
| `.matchedGeometryEffect` | iOS 14 | animation-patterns-transitions.md |
| `.transition(.push(from:))` | iOS 16 | animation-patterns-transitions.md |
| `.contentTransition(.numericText())` | iOS 16 | animation-patterns-transitions.md |
| `PhaseAnimator` | iOS 17 | animation-patterns-phase-keyframe-animators.md |
| `KeyframeAnimator` | iOS 17 | animation-patterns-phase-keyframe-animators.md |
| `.spring(duration:bounce:)` | iOS 17 | animation-patterns-core-animations.md |
| Spring presets (`.bouncy`, `.snappy`, `.smooth`) | iOS 17 | animation-patterns-core-animations.md |
| `withAnimation(_:completionCriteria:_:completion:)` | iOS 17 | animation-patterns-core-animations.md |
| `.symbolEffect()` | iOS 17 | animation-patterns-symbol-effects.md |
| `.transition(.blurReplace)` | iOS 17 | animation-patterns-transitions.md |
| `.contentTransition(.symbolEffect(.replace))` | iOS 17 | animation-patterns-transitions.md |
| `Transition` protocol / `TransitionPhase` | iOS 17 | animation-patterns-transitions.md |
| `TransactionKey`, scoped `.animation` / `.transaction` variants | iOS 17 | animation-patterns-core-animations.md |
| `KeyframeTimeline`, `.mapCameraKeyframeAnimator` | iOS 17 | animation-patterns-phase-keyframe-animators.md |
| `.scrollTransition`, `.visualEffect` | iOS 17 | animation-patterns-visual-effects.md |
| Shaders: `.colorEffect` / `.distortionEffect` / `.layerEffect` | iOS 17 | animation-patterns-visual-effects.md |
| `MeshGradient` | iOS 18 | animation-patterns-visual-effects.md |
| `TextRenderer` / `TextAttribute` | iOS 18 | animation-patterns-visual-effects.md |

## Common Mistakes — Quick Reference

| # | Mistake | Fix | Details |
|---|---------|-----|---------|
| 1 | `spring(response:bounce:)` — mixing parameter generations | Use either `spring(response:dampingFraction:)` (iOS 13) or `spring(duration:bounce:)` (iOS 17) | animation-patterns-core-animations.md |
| 2 | `.animation(.spring())` without `value:` parameter | Always pass `value:` — the no-value variant is deprecated (iOS 15) | animation-patterns-core-animations.md |
| 3 | Wrong PhaseAnimator closure signature | `PhaseAnimator(phases) { content, phase in }` — not `{ phase in }` | animation-patterns-phase-keyframe-animators.md |
| 4 | Using `withAnimation` for SF Symbol effects | Use `.symbolEffect()` modifier instead | animation-patterns-symbol-effects.md |

## Review Checklist

When reviewing animation code, verify:

- [ ] **Reduce motion** — animations respect `accessibilityReduceMotion`; provide non-motion alternatives
- [ ] **Duration limits** — no animation exceeds ~0.5s for UI feedback; longer only for decorative/ambient effects
- [ ] **Spring vs linear** — springs for interactive/physical motion; linear/easeInOut only for opacity fades or progress indicators
- [ ] **No deprecated APIs** — `.animation(.spring())` without `value:` is deprecated; `.animation(nil)` is replaced by `withTransaction`
- [ ] **Correct spring generation** — parameter names match the same API generation (never mix `response` with `bounce`)
- [ ] **Completion handlers** — using `withAnimation(_:completionCriteria:_:completion:)` (iOS 17+), not inventing `.onAnimationCompleted`
- [ ] **Transition scope** — `.transition()` only affects views inside `if`/`switch` controlled by state; not for views that are always present
- [ ] **Per-frame closures stay cheap** — KeyframeAnimator `content` closures, `visualEffect` closures, `TextRenderer.draw`, and `Animatable` view bodies run every frame; no allocation, formatting, or layout math inside

## Reference Files

| File | Content |
|------|---------|
| [animation-patterns-core-animations.md](animation-patterns-core-animations.md) | withAnimation, springs, completions, transactions + TransactionKey, timing curves, Animatable mechanics, fluid-interface principles (momentum projection, rubber-banding, hysteresis) |
| [animation-patterns-phase-keyframe-animators.md](animation-patterns-phase-keyframe-animators.md) | PhaseAnimator, KeyframeAnimator, KeyframeTimeline, MapKit camera keyframes, custom animations |
| [animation-patterns-transitions.md](animation-patterns-transitions.md) | View transitions, custom Transition protocol, matched geometry, gesture-driven springs |
| [animation-patterns-symbol-effects.md](animation-patterns-symbol-effects.md) | SF Symbol effects, accessibility |
| [animation-patterns-visual-effects.md](animation-patterns-visual-effects.md) | scrollTransition, visualEffect, MeshGradient, TextRenderer, shader effects (colorEffect/distortionEffect/layerEffect), effect pipelines, semantic alignment guides |

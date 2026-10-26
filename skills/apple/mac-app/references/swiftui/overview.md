# SwiftUI overview

<a id="source-swiftui-skill-md"></a>
## Source: `swiftui/SKILL.md`

# SwiftUI Skills

Focused SwiftUI framework skills — each sub-skill covers one API area in depth.

## When This Skill Activates

Use this skill when the user:
- Has **state/rendering bugs**: state resets, over-rendering, flashing lists, animation crossfades (data-flow)
- Is choosing **@State vs @Bindable vs @Environment** or migrating to Observation (data-flow)
- Builds **custom layouts or containers**, or fights **lazy-stack/scroll performance** (layout)
- Wants alarms or timers with **AlarmKit** (custom UI, Live Activities, snooze)
- Is creating **3D data visualizations** with Swift Charts (Chart3D, SurfacePlot)
- Needs **styled text or rich text editing** (Text, AttributedString, TextEditor)
- Is implementing or customizing **toolbars** (customizable toolbars, search integration)
- Wants to **embed web content** (WebView, WebPage, JavaScript interop)

## Available Skills

The links below point to this skill's local references.

| Skill | Read | Covers |
|-------|------|--------|
| data-flow | [Data flow](data-flow.md) | View identity/lifetime/dependencies, Observation, state ownership, body discipline, main-actor contract |
| layout | [Layout](layout.md) | Layout protocol, Grid decisions, custom containers, lazy-stack + scrolling performance rules |
| alarmkit | [AlarmKit](alarmkit.md) | Alarms and timers with custom UI, Live Activities, snooze (iOS 18+) |
| charts-3d | [3D charts](charts-3d.md) | Chart3D, SurfacePlot, interactive pose control, surface styling |
| text-editing | [Text editing](text-editing.md) | Text, AttributedString, TextEditor with formatting controls |
| toolbars | [Toolbars](toolbars.md) | Customizable toolbars, search integration, transition effects, platform behavior |
| webkit | [WebKit](webkit.md) | WebView and WebPage embedding, navigation, JavaScript interop |

## How to Route

1. Match the request to a row above.
2. Read the linked reference plus any supporting files it lists.
3. Apply the guidance to the user's code.

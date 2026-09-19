# Screen reader testing

Screen reader testing is **manual** — no agent, including one with browser tool access (Claude's built-in browser tools or a browser MCP server such as Safari Technology Preview's), can drive a screen reader or hear its output. Those tools can inspect the accessibility tree structurally (see [manual-checks.md](manual-checks.md)), but that's not the same as verifying what VoiceOver, NVDA, or JAWS actually announces. This is a reference for you to test with, or to share with clients.

## Testing priority

| Priority          | Screen reader | Browser           | Platform |
| ----------------- | ------------- | ----------------- | -------- |
| 1 (minimum)       | VoiceOver     | Safari            | macOS    |
| 2 (minimum)       | VoiceOver     | Safari            | iOS      |
| 3 (recommended)   | NVDA          | Firefox or Chrome | Windows  |
| 4 (comprehensive) | JAWS          | Chrome            | Windows  |
| 5 (comprehensive) | TalkBack      | Chrome            | Android  |

NVDA and JAWS cover ~71% of screen reader users (Windows). VoiceOver covers ~15% (macOS/iOS). Test the minimum set first.

---

## VoiceOver — macOS

**Enable:** System Settings → Accessibility → VoiceOver, or `Cmd + F5`  
**VO modifier:** `Ctrl + Option` (shown as `VO` below)

### Navigation

| Key                    | Action                                                     |
| ---------------------- | ---------------------------------------------------------- |
| `VO + →` / `VO + ←`    | Next / previous element                                    |
| `VO + Shift + ↓` / `↑` | Enter / exit group                                         |
| `Tab` / `Shift + Tab`  | Next / previous focusable element                          |
| `VO + U`               | Open rotor (navigate by headings, links, forms, landmarks) |
| `VO + Cmd + H`         | Next heading                                               |
| `VO + Cmd + L`         | Next link                                                  |
| `VO + Cmd + J`         | Next form control                                          |

### Interaction

| Key          | Action           |
| ------------ | ---------------- |
| `VO + Space` | Activate element |
| `VO + A`     | Read from cursor |
| `Ctrl`       | Stop speaking    |

### Checklist

- [ ] Page title announced on load
- [ ] Skip link works
- [ ] All headings discoverable via rotor; hierarchy logical
- [ ] Form labels read before inputs
- [ ] Error messages announced
- [ ] Modal announced as dialog; focus trapped inside; restored on close
- [ ] `aria-live` regions announce dynamic updates without focus change
- [ ] All buttons and links have meaningful names

---

## VoiceOver — iOS

**Enable:** Settings → Accessibility → VoiceOver, or triple-press side button

| Gesture                   | Action                                         |
| ------------------------- | ---------------------------------------------- |
| Swipe right / left        | Next / previous element                        |
| Double-tap                | Activate element                               |
| Two-finger swipe up       | Read all                                       |
| Three-finger swipe        | Scroll                                         |
| Rotor (two-finger rotate) | Change navigation mode (headings, links, etc.) |

---

## NVDA — Windows

**Download:** nvaccess.org (free)  
**Recommended browser:** Firefox or Chrome  
**NVDA modifier:** `Insert` or `Caps Lock`

| Key               | Action                                     |
| ----------------- | ------------------------------------------ |
| `NVDA + ↓`        | Read from cursor                           |
| `H` (browse mode) | Next heading                               |
| `K`               | Next link                                  |
| `F`               | Next form field                            |
| `D`               | Next landmark                              |
| `Tab`             | Next focusable element                     |
| `Enter`           | Activate / enter forms mode                |
| `Esc`             | Exit forms mode                            |
| `NVDA + F7`       | Elements list (headings, links, landmarks) |

---

## JAWS — Windows

**Note:** JAWS requires a licence. Use NVDA for most testing; reserve JAWS for client requirements or enterprise contexts.  
**Recommended browser:** Chrome  
**JAWS modifier:** `Insert`

| Key           | Action                 |
| ------------- | ---------------------- |
| `H`           | Next heading           |
| `Tab`         | Next focusable element |
| `F`           | Next form field        |
| `R`           | Next landmark region   |
| `Insert + F6` | Headings list          |
| `Insert + F7` | Links list             |
| `Insert + F5` | Form fields list       |

---

## What to verify in all screen readers

1. **Page title** — announced on load
2. **Skip link** — reachable and functional
3. **Headings** — all discoverable; hierarchy logical
4. **Landmarks** — main, nav, aside present and labelled
5. **Links** — all have descriptive names; no "click here"
6. **Buttons** — all have accessible names
7. **Images** — alt text announced; decorative images skipped
8. **Forms** — labels read before inputs; errors announced; required fields indicated
9. **Modals** — announced as dialog; focus trapped; restored on close
10. **Live regions** — status updates announced without focus change

# Native Mac behaviour

Adapted from the pinned mac-arsed Mac app guidance listed in [SOURCE.md](../../SOURCE.md). Check current Apple documentation before using version-specific API claims.

## Plan the Mac workflow

First classify the app as a document editor, library, utility, professional workspace, viewer or hybrid. Name its core objects and decide what can be opened, saved, selected, dragged, copied, imported, exported, shown in another window and undone. For a new app, deliver an affordance map for each major screen, list, editor and command. Include the native control, selection, keyboard, copy and paste, drag and drop, context menu, saved state and accessibility role. Also deliver a command and menu plan, a window and document plan, an interoperability plan, a settings and state plan, an accessibility plan and manual QA cases.

Choose a document window, secondary window, tab, inspector panel, sheet, popover or split view for the work each contains. Document apps should consider standard open and save panels, autosave, versions, recent documents and multiple windows. A utility may need only a menu bar item and a settings window. Decide this before arranging controls in a single window.

## Check native behaviour

- Prefer native text fields, tables, outlines, search fields, split views, toolbars and panels. A custom control must provide the expected focus ring, keyboard handling, selection, pointer feedback, context menu, appearance changes, accessible role and actions, and undo where it edits state.
- Give the app meaningful App, File, Edit, View, Window and Help menus as applicable. Place important commands in the menu bar or a suitable context menu; use standard names and shortcuts, and enable commands according to focus and selection.
- Support arrow navigation, Tab and Shift-Tab, Return, Escape, Delete, type-to-select and standard Command shortcuts where they fit. Do not take a familiar shortcut for a surprising action.
- Keep native text editing behaviour, including word and line movement, selection, spelling and substitutions, input methods, composed characters and bidirectional text. Test selection while scrolling.
- In collections, make Shift-click extend a range and Command-click toggle items. A context action on a selected item acts on the whole selection. Keep selection visually distinct from keyboard focus.
- Let useful objects move within and between windows, into the app from Finder and out to another app. Consider files, URLs, images, folders, generated file promises and modifier-key copy or move behaviour. A drag target must show what it accepts.
- Put useful public formats on the pasteboard, with a plain text fallback when possible. Accept common formats on paste. Check how selected rows, files, rich text, images and URLs appear in other apps, not just inside the source app.
- Treat edits, deletes, moves and reorders as undoable end to end. Register changes with the appropriate undo manager, name actions clearly and verify redo restores the change.
- Preserve meaningful window sizes and positions, split and sidebar widths, columns, sort order, view modes, disclosure state, toolbar choices and per-document view state. Do not save transient dialog positions. Offer useful defaults and reveal deeper controls through settings, context menus, inspectors and optional toolbar items.
- Consider Finder, Services, Shortcuts, Terminal, open and save panels, import and export, sharing and public file types where the app's objects call for them.

## Review Mac behaviour

Review native controls, commands, keyboard and focus, text, selection, drag and drop, pasteboard formats, windows and documents, saved state, system integration, accessibility and craft separately. For each area, describe a concrete gap and its effect; do not infer behaviour from a screenshot. A Mac-specific accessibility pass checks full keyboard access, VoiceOver order and actions, custom control roles and values, contrast and appearance changes, reduced motion and usable focus in every window and sheet.

Try the actions a Mac user may reasonably expect: Command-A/C/X/V/Z in each context; Shift-click and Command-click in collections; copy rows into TextEdit; paste rich content into rich and plain text targets; drag files from Finder, content out to Finder and content between app windows; use the Window menu with multiple documents; resize columns and relaunch; navigate without a mouse; use VoiceOver; try dark mode, high contrast, reduced motion and multiple display sizes; undo edits and reorders; open files with unusual names and locations. If the app cannot run locally, hand these over as manual checks rather than claiming they passed.

Flag a web-like shell with empty menus, toolbar-only actions, incomplete custom text controls, single selection where batch work is natural, context menus that discard the selection, a fixed single window that hinders comparison, absent drag or copy support, and forgotten user layout choices. When adapting such an app, keep its useful product model and rebuild the Mac interaction around commands, windows, native controls and public data formats. Before delivery, confirm the app's core objects participate in the expected menus, keyboard actions, windows, pasteboard, undo and assistive technology workflows.

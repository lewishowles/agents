---
name: mac-app
description: >
  Use this skill when planning, building or reviewing a native macOS app, including its windows, menus, AppKit and SwiftUI integration, data, design, performance or testing. Load only the relevant topic reference. Do not use it for an iPhone-only app or general Swift work without a Mac app.
---

# Mac app

Choose the task's topic below and open only its reference. Where a topic has named supporting files, open the part that covers the question. For general Swift and SwiftUI code guidance, also use [`swift`](../../swift/swift/SKILL.md).

## macOS

- [Native Mac behaviour](references/macos/native-mac-behaviour.md): Plan or review windows, menus, selection, pasteboard, undo, accessibility and interoperability.
- [Overview](references/macos/overview.md): Find the upstream Mac modules and their intended use.
- [App planner](references/macos/app-planner.md): Plan a new Mac app or assess an existing one.
- [AppKit–SwiftUI bridge](references/macos/appkit-swiftui-bridge.md): Choose a bridge; open its named parts for hosting, view representation or state.
- [Architecture patterns](references/macos/architecture-patterns.md): Choose app structure; open named parts for patterns, modules or SOLID guidance.
- [Coding best practices](references/macos/coding-best-practices.md): Review code organisation; open named parts for architecture, persistence, concurrency or Swift language guidance.
- [Mac capabilities](references/macos/macos-capabilities.md): Plan system features; open named parts for background work, extensions, menu bar apps or sandboxing.
- [macOS Tahoe APIs](references/macos/macos-tahoe-apis.md): Check the pinned source's Tahoe features, continuity, intelligence and Xcode guidance.
- [SwiftData architecture](references/macos/swiftdata-architecture.md): Design a data layer; open named parts for performance, queries, repositories or schemas.
- [Tahoe UI review](references/macos/ui-review-tahoe.md): Review Mac UI; open named parts for accessibility, AppKit, Liquid Glass or SwiftUI.

## Swift

- [Overview](references/swift/overview.md): Find the upstream Swift modules and their intended use.
- [Concurrency](references/swift/concurrency.md): Check Swift 6.2 isolation and migration behaviour.
- [Concurrency patterns](references/swift/concurrency-patterns.md): Choose async patterns; open named parts for actors, continuations, migration or structured concurrency.
- [Memory](references/swift/memory.md): Review memory ownership and lifetime in Mac code.

## SwiftUI

- [Overview](references/swiftui/overview.md): See which SwiftUI guide covers a task when the right one is unclear.
- [Data flow](references/swiftui/data-flow.md): Trace view identity, state lifetime, Observation and updates.
- [Layout](references/swiftui/layout.md): Build custom layouts and containers or diagnose scrolling performance.
- [AlarmKit](references/swiftui/alarmkit.md): Build alarm UI; open named parts for Live Activities, presentation or scheduling.
- [3D charts](references/swiftui/charts-3d.md): Build or review a 3D chart.
- [Text editing](references/swiftui/text-editing.md): Build a SwiftUI text editor.
- [Toolbars](references/swiftui/toolbars.md): Design or review a Mac toolbar.
- [WebKit](references/swiftui/webkit.md): Embed web content; open named parts for JavaScript, navigation or basic web views.

## SwiftData

- [Overview](references/swiftdata/overview.md): See which SwiftData guide covers a task when the right one is unclear.
- [SwiftData inheritance](references/swiftdata/inheritance.md): Model inherited data types.

## Foundation

- [Overview](references/foundation/overview.md): See which Foundation guide covers a task when the right one is unclear.
- [Attributed strings](references/foundation/attributed-string.md): Work with attributed text and text attributes.

## Design

- [Overview](references/design/overview.md): Find the upstream design topics.
- [Animation patterns](references/design/animation-patterns.md): Choose animation; open named parts for animation basics, keyframes, symbols or transitions.
- [Liquid Glass](references/design/liquid-glass.md): Review or apply the pinned source's Liquid Glass guidance.

## Performance

- [Profiling](references/performance/profiling.md): Plan an Instruments investigation; open named parts for energy, launch, memory or time profiling.
- [SwiftUI debugging](references/performance/swiftui-debugging.md): Investigate view updates; open named parts for body evaluation, loading, identity or common pitfalls.

## Testing

- [Overview](references/testing/overview.md): Find the upstream testing topics.
- [Characterisation tests](references/testing/characterization-test-generator.md): Capture current behaviour before changing it.
- [Integration test scaffold](references/testing/integration-test-scaffold.md): Set up an integration test.
- [Snapshot test setup](references/testing/snapshot-test-setup.md): Set up snapshot coverage.
- [TDD bug fix](references/testing/tdd-bug-fix.md): Reproduce a bug before fixing it.
- [TDD feature](references/testing/tdd-feature.md): Drive a feature from a failing test.
- [TDD refactor guard](references/testing/tdd-refactor-guard.md): Protect behaviour during refactoring.
- [Test contract](references/testing/test-contract.md): Define observable test expectations.
- [Test data factory](references/testing/test-data-factory.md): Create repeatable test inputs.

Version-specific claims describe the [pinned source](SOURCE.md), not a live API contract. Check the project's deployment target and current Apple documentation before using an API or recommending a platform convention.

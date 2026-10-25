---
name: iphone-app
description: >
  Use this skill when planning, building, migrating or reviewing a native iPhone or
  iPad app, including iOS architecture, navigation, iPad interactions, Assistive
  Access, interface design and accessibility. Open only the relevant reference.
  Do not use it for a Mac-only app or general Swift work without an iOS app.
---

# iPhone app

Choose the task's topic below and open only its reference. Where a topic has
supporting files, open the part that covers the question. For general Swift and
SwiftUI code guidance, also use [`swift`](../../swift/swift/SKILL.md) and
[`swift-ui`](../../swift/swift-ui/SKILL.md).

## App planning

- [Overview](references/overview.md): Find the iOS topics and their intended use.
- [App planner](references/app-planner/overview.md): Plan a new iPhone app or assess an existing one. Open [architecture](references/app-planner/architecture-guide.md), the [planning checklist](references/app-planner/planning-checklist.md) or [tech stack options](references/app-planner/tech-stack-options.md) when needed.

## Code and migration

- [Coding best practices](references/coding-best-practices/overview.md): Review iOS code organisation. Open [architecture patterns](references/coding-best-practices/architecture-patterns.md), [Core Data patterns](references/coding-best-practices/coredata-patterns.md), [Swift patterns](references/coding-best-practices/swift-patterns.md) or [SwiftUI patterns](references/coding-best-practices/swiftui-patterns.md) for the affected code. An [optional SwiftLint example](references/coding-best-practices/rules/swiftlint.yml) covers selected rules when the app uses SwiftLint.
- [Migration patterns](references/migration-patterns/overview.md): Plan an incremental move from [Core Data to SwiftData](references/migration-patterns/coredata-to-swiftdata.md), [Objective-C to Swift](references/migration-patterns/objc-to-swift.md), [ObservableObject to Observable](references/migration-patterns/observable-migration.md), [StoreKit 1 to 2](references/migration-patterns/storekit-migration.md), [UIKit to SwiftUI](references/migration-patterns/uikit-to-swiftui.md) or [XCTest to Swift Testing](references/migration-patterns/xctest-to-swift-testing.md).

## Interface and accessibility

- [Accessibility audit](references/accessibility-audit/overview.md): Check an iOS or iPadOS app with [automated audits](references/accessibility-audit/automated-audits.md), manual assistive technology passes and [App Store Accessibility Nutrition Labels](references/accessibility-audit/nutrition-labels.md).
- [Assistive Access](references/assistive-access/overview.md): Design a simplified iOS experience for Assistive Access.
- [iPad patterns](references/ipad-patterns/overview.md): Plan iPad multitasking and input. Open [multitasking](references/ipad-patterns/multitasking.md), [input methods](references/ipad-patterns/input-methods.md) or [drag and drop](references/ipad-patterns/drag-drop.md) for the affected interaction.
- [Navigation patterns](references/navigation-patterns/overview.md): Choose an iOS navigation structure. Open [NavigationStack](references/navigation-patterns/navigation-stack.md), [NavigationSplitView](references/navigation-patterns/navigation-split-view.md), [TabView](references/navigation-patterns/tab-view.md), [programmatic navigation](references/navigation-patterns/programmatic-navigation.md) or [navigation transitions](references/navigation-patterns/navigation-transitions.md) as needed.
- [UI review](references/ui-review/overview.md): Review the iOS interface against the [HIG checklist](references/ui-review/hig-checklist.md), [font guidance](references/ui-review/font-guidelines.md) and [accessibility quick reference](references/ui-review/accessibility-quick-ref.md).

## Related Mac references

For shared Apple platform material, open the relevant Mac app reference rather than
copying it here: [Swift](../mac-app/references/swift/overview.md),
[SwiftUI](../mac-app/SKILL.md#swiftui),
[SwiftData](../mac-app/SKILL.md#swiftdata),
[testing](../mac-app/references/testing/overview.md) or
[accessibility](../mac-app/references/macos/ui-review-tahoe-accessibility.md).
Check platform-specific advice before applying a Mac reference to iOS.

Version-specific claims describe the [pinned source](SOURCE.md), not a live API
contract. Check the project's deployment target and current Apple documentation
before using an API or recommending a platform convention.

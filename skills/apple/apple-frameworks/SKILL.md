---
name: apple-frameworks
description: >
  Use this skill when planning, building or reviewing Apple Intelligence, App Intents, Foundation Models, Core ML, GeoToolbox, privacy or security features in an Apple app. Open only the relevant topic reference. Do not use it for general Swift work without one of these frameworks.
---

# Apple frameworks

Choose the task's topic below and open only its reference. Where a topic has named supporting files, open the part that covers the question. For general Swift and SwiftUI code guidance, also use [`swift`](../../swift/swift/SKILL.md).

## Apple Intelligence

- [Overview](references/apple-intelligence/overview.md): Find the pinned source's Apple Intelligence topics and their intended use.
- [App Intents](references/apple-intelligence/app-intents.md): Add Siri actions, Shortcuts, Spotlight indexing or interactive snippets; open its named parts for implementation detail. See also [macOS Tahoe APIs](../mac-app/references/macos/macos-tahoe-apis.md) and [AlarmKit Live Activities](../mac-app/references/swiftui/alarmkit-live-activities.md).
- [Foundation Models](references/apple-intelligence/foundation-models.md): Work with on-device text generation, structured output, tool calling or sessions; open its named parts for model safety, agents and utilities.
- [Visual Intelligence](references/apple-intelligence/visual-intelligence.md): Connect camera-based search to app content.

## Core ML

- [Overview](references/core-ml/overview.md): Choose Core ML, Create ML, Vision or Natural Language work; open named parts for architecture patterns and templates.

## MapKit

- [Overview](references/mapkit/overview.md): Find the MapKit references; the pinned source covers only GeoToolbox.
- [GeoToolbox](references/mapkit/geotoolbox.md): Work with place descriptors, geocoding or cross-service location data.

## Security

- [Overview](references/security/overview.md): See which security topics the pinned source still covers, and why the general guidance was removed.
- [Privacy manifests](references/security/privacy-manifests.md): Prepare required reason API, tracking and third-party SDK declarations.
- [SwiftLint rule](references/security/rules/swiftlint.yml): Check for hardcoded secret literals in Swift source.

Version-specific claims describe the [pinned source](SOURCE.md), not a live API contract. Check the project's deployment target and current Apple documentation before using an API or recommending a platform convention.

---
name: apple-generators
description: >
  Use this skill when generating Swift code or project files for a feature of an Apple
  app, such as networking, persistence and iCloud sync, sign-in, push notifications,
  widgets, onboarding, settings, a StoreKit paywall or subscriptions, CI/CD or tests.
  Choose a generator by what it builds, then open only that reference and its named
  templates or patterns. Do not use it for general Swift advice without a component to
  build.
---

# Apple code generators

Choose the generator below by what the app needs to build. Open its overview first,
then only the supporting files it names. Check the project structure, deployment
target and existing implementation before applying a template. For general Swift
and SwiftUI code guidance, also use [`swift`](../../swift/swift/SKILL.md) and
[`swift-ui`](../../swift/swift-ui/SKILL.md).
App Store planning, such as custom product pages, in-app events and offer codes,
is in [`app-release`](../app-release/SKILL.md).

## App plumbing

- [analytics-setup](references/analytics-setup/overview.md): Build protocol-based analytics infrastructure with swappable providers (TelemetryDeck, Firebase, Mixpanel).
- [app-clip](references/app-clip/overview.md): Build App Clip targets with invocation URL handling, lightweight experiences, and full app upgrade prompts.
- [app-extensions](references/app-extensions/overview.md): Build app extension infrastructure for Share Extensions, Action Extensions, Keyboard Extensions, and Safari Web Extensions with data sharing via App Groups.
- [auth-flow](references/auth-flow/overview.md): Build authentication infrastructure with Sign in with Apple, biometrics, and Keychain storage.
- [background-processing](references/background-processing/overview.md): Build background processing infrastructure with BGTaskScheduler, background refresh, background downloads, and silent push handling.
- [cloudkit-sync](references/cloudkit-sync/overview.md): Build CloudKit sync infrastructure using CKSyncEngine with conflict resolution, sharing, and account monitoring.
- [data-export](references/data-export/overview.md): Build data export/import infrastructure for JSON, CSV, PDF formats with GDPR data portability, share sheet integration, and file import.
- [deep-linking](references/deep-linking/overview.md): Build deep linking infrastructure with URL schemes, Universal Links, and App Intents for Siri/Shortcuts.
- [error-monitoring](references/error-monitoring/overview.md): Build protocol-based error/crash monitoring with swappable providers (Sentry, Crashlytics).
- [feature-flags](references/feature-flags/overview.md): Build feature flag infrastructure with local defaults, remote configuration, SwiftUI integration, and debug menu.
- [http-cache](references/http-cache/overview.md): Build an HTTP caching layer with Cache-Control parsing, ETag/conditional requests, and offline fallback.
- [image-loading](references/image-loading/overview.md): Build an image loading pipeline with memory/disk caching, deduplication, and a CachedAsyncImage SwiftUI view.
- [live-activity-generator](references/live-activity-generator/overview.md): Build ActivityKit Live Activity infrastructure with Dynamic Island layouts, Lock Screen presentation, and push-to-update support.
- [localization-setup](references/localization-setup/overview.md): Build localisation infrastructure for multi-language support in iOS and macOS apps.
- [logging-setup](references/logging-setup/overview.md): Build structured logging infrastructure using os.log/Logger to replace print() statements.
- [networking-layer](references/networking-layer/overview.md): Build a protocol-based networking layer with async/await, error handling, and swappable implementations.
- [offline-queue](references/offline-queue/overview.md): Build an offline operation queue with persistence, automatic retry on connectivity, and conflict resolution.
- [pagination](references/pagination/overview.md): Build pagination infrastructure with offset or cursor-based patterns, infinite scroll, and search support.
- [persistence-setup](references/persistence-setup/overview.md): Build a SwiftData or Core Data persistence layer with optional iCloud sync.
- [push-notifications](references/push-notifications/overview.md): Build push notification infrastructure with APNs registration, handling, and rich notifications.
- [state-restoration](references/state-restoration/overview.md): Build state preservation and restoration infrastructure for navigation paths, tab selection, scroll positions, and form data across app launches and background termination.
- [widget-generator](references/widget-generator/overview.md): Build WidgetKit widgets for iOS/macOS home screen and lock screen with timeline providers, interactive elements, and App Intent configuration.

## Screens and engagement

- [announcement-banner](references/announcement-banner/overview.md): Build an in-app announcement banner system with remote configuration, scheduling, deep link actions, and dismiss tracking.
- [feedback-form](references/feedback-form/overview.md): Build an in-app feedback form with optional screenshots and device diagnostics, and route feedback to support or App Store reviews.
- [lapsed-user](references/lapsed-user/overview.md): Build lapsed user detection and re-engagement screens with personalised return experiences, win-back offers, and inactivity tracking.
- [milestone-celebration](references/milestone-celebration/overview.md): Build achievement celebration UI with confetti animations, badge unlocks, progress milestones, haptic feedback, and optional share-to-social.
- [onboarding-generator](references/onboarding-generator/overview.md): Build multi-step onboarding flows with persistence for iOS/macOS apps.
- [permission-priming](references/permission-priming/overview.md): Build pre-permission priming screens that explain benefits before showing iOS system permission dialogs.
- [quick-win-session](references/quick-win-session/overview.md): Build guided first-action flows that help users achieve a meaningful result within 60 seconds to boost retention.
- [referral-system](references/referral-system/overview.md): Build referral/invite infrastructure with unique codes, deep link sharing, reward tracking, and fraud prevention.
- [review-prompt](references/review-prompt/overview.md): Build smart App Store review prompt infrastructure with configurable conditions and platform detection.
- [settings-screen](references/settings-screen/overview.md): Build a complete settings screen for iOS/macOS apps with common sections.
- [share-card](references/share-card/overview.md): Build shareable card images from app content (achievements, stats, quotes) for social media sharing.
- [social-export](references/social-export/overview.md): Build infrastructure for exporting app content to social platforms (Instagram Stories, TikTok, Twitter/X) with platform-specific formatting, aspect ratios, and metadata.
- [spotlight-indexing](references/spotlight-indexing/overview.md): Build Core Spotlight indexing infrastructure for making app content searchable via system Spotlight with rich attributes and deep link integration.
- [streak-tracker](references/streak-tracker/overview.md): Build a streak tracking system with timezone-aware day boundaries, streak freeze protection, and streak-at-risk push notifications.
- [tipkit-generator](references/tipkit-generator/overview.md): Build TipKit infrastructure with inline/popover tips, rules, display frequency, and testing utilities.
- [usage-insights](references/usage-insights/overview.md): Build user-facing usage statistics, activity summaries, and personalised insights dashboards (weekly recaps, year-in-review, Spotify Wrapped-style).
- [variable-rewards](references/variable-rewards/overview.md): Build a variable reward system with randomised rewards, daily bonuses, mystery box mechanics, and ethical engagement caps.
- [watermark-engine](references/watermark-engine/overview.md): Build a watermark overlay system for images and video with configurable positioning, opacity, tiling, and paywall integration for automatic removal on subscription or purchase.
- [whats-new](references/whats-new/overview.md): Build a "What's New" / changelog screen shown after app updates with version tracking, feature highlights, and one-time display per version.

## Purchases and account

- [account-deletion](references/account-deletion/overview.md): Build an Apple-compliant account deletion flow with multi-step confirmation UI, optional data export, configurable grace period, Keychain cleanup, and server-side deletion request.
- [consent-flow](references/consent-flow/overview.md): Build GDPR/CCPA/DPDP privacy consent flows with granular category preferences, consent state persistence, audit logging, and ATT (App Tracking Transparency) integration.
- [force-update](references/force-update/overview.md): Build a minimum version enforcement system with hard-block and soft-prompt update flows, App Store redirect, and remote config or App Store lookup for version checks.
- [paywall-generator](references/paywall-generator/overview.md): Build a StoreKit 2 subscription paywall with SwiftUI views.
- [promoted-iap](references/promoted-iap/overview.md): Set up promoted in-app purchases with StoreKit 2 product configuration, paywall integration, and App Store product page display.
- [subscription-lifecycle](references/subscription-lifecycle/overview.md): Manage StoreKit 2 subscription status, grace periods, billing retries, offer codes and plan changes.
- [subscription-offers](references/subscription-offers/overview.md): Build introductory, promotional, offer code and win-back offers with eligibility checks and presentation.
- [win-back-offers](references/win-back-offers/overview.md): Build a win-back offer flow for former subscribers with eligibility checks, offer presentation and analytics.

## Build and quality

- [accessibility-generator](references/accessibility-generator/overview.md): Build accessibility infrastructure for VoiceOver, Dynamic Type, and accessibility features.
- [app-icon-generator](references/app-icon-generator/overview.md): Build app icons programmatically using CoreGraphics following Apple HIG.
- [ci-cd-setup](references/ci-cd-setup/overview.md): Build CI/CD configuration for automated builds, tests, and distribution of iOS/macOS apps.
- [debug-menu](references/debug-menu/overview.md): Build a developer menu for feature flags, environments, network logs, caches and diagnostics in debug builds.
- [screenshot-automation](references/screenshot-automation/overview.md): Build an automated App Store screenshot pipeline with UI tests for screenshot capture, device framing, localised caption overlays, and multi-size batch export.
- [test-generator](references/test-generator/overview.md): Build test templates for unit tests, integration tests, and UI tests using Swift Testing and XCTest.

Version-specific claims describe the [pinned source](SOURCE.md), not a live API
contract. Check current Apple documentation before using an API or recommending
a platform convention.

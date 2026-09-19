---
name: swift-ui
description: >
  Use this skill when writing or reviewing SwiftUI code — views, state management, view composition, navigation, and performance. Covers modern patterns (@Observable, @Bindable), anti-patterns (ObservableObject, @Published), and optimization techniques for responsive interfaces.
filePatterns: ["*.swift"]
pathPatterns: []
---
# SwiftUI patterns

Modern SwiftUI, iOS 26+ / macOS 26+. Prefer `@Observable` over `ObservableObject`, type-safe navigation, performance-aware composition.

## State management

### Property wrapper selection

Choose by scope and mutability:

| Wrapper              | Scope             | Mutability      | Use case                                                       |
| -------------------- | ----------------- | --------------- | -------------------------------------------------------------- |
| `@State`             | Single view       | Mutable         | Simple local state (toggle, text field)                        |
| `@Binding`           | Parent ↔ child    | Mutable         | Pass mutable state to child                                    |
| `@Observable`        | View model        | Mutable         | Multi-view shared state (modern, recommended)                  |
| `@Bindable`          | Observable access | Mutable binding | Get bindings from Observable in `@Environment`-injected models |
| `@Environment`       | App-wide          | Read-only       | Access app-level config or services                            |
| `@EnvironmentObject` | App-wide          | Deprecated      | Use `@Environment` + `@Observable` instead                     |

### @Observable view model pattern

Replace `ObservableObject` + `@Published` + `@StateObject` with `@Observable`:

```swift
import Observation

@Observable
@MainActor
final class ProjectViewModel {
  var projects: [Project] = []
  var selectedProjectID: UUID?
  var isLoading = false

  func loadProjects() async {
    isLoading = true
    defer { isLoading = false }
    projects = await ProjectService.fetch()
  }
}

struct ProjectView: View {
  @State var model = ProjectViewModel()

  var body: some View {
    List(model.projects) { project in
      ProjectRow(project: project)
    }
    .task {
      await model.loadProjects()
    }
  }
}
```

### Environment injection pattern

Inject Observable models via `@Environment`; access with `@Bindable`:

```swift
// In parent
.environment(authModel)

// In child — read-only
struct LoginView: View {
  @Environment(AuthViewModel.self) var auth
  var body: some View { Text(auth.username) }
}

// In child — mutable binding
struct SettingsView: View {
  @Environment(SettingsViewModel.self) var settings
  var body: some View {
    Form {
      @Bindable var settings = settings
      Toggle("Notifications", isOn: $settings.notificationsEnabled)
    }
  }
}
```

For view composition, navigation, performance, previews, and anti-patterns, see [references/patterns.md](references/patterns.md).

> Modified from [ECC `swiftui-patterns`](https://github.com/affaan-m/everything-claude-code/blob/main/skills/swiftui-patterns/SKILL.md) — MIT © 2026 Affaan Mustafa.

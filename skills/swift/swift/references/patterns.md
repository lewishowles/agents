# SwiftUI — patterns

## View composition

### Subview extraction

Avoid re-rendering the entire view tree on local state changes. Extract sub-views with their own `@State`:

```swift
struct ContentView: View {
  @State var activeTab = 0

  var body: some View {
    TabView(selection: $activeTab) {
      Tab1View()  // own @State — doesn't re-render with activeTab change
      Tab2View()
    }
  }
}

struct Tab1View: View {
  @State var textInput = ""

  var body: some View {
    TextField("Enter...", text: $textInput)
  }
}
```

### ViewModifier pattern

```swift
struct PrimaryButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color.blue)
      .foregroundColor(.white)
      .cornerRadius(8)
  }
}

extension View {
  func primaryButton() -> some View {
    modifier(PrimaryButtonModifier())
  }
}

Button("Submit") { }.primaryButton()
```

## Navigation

### Type-safe NavigationStack

Enum-based routing with `NavigationPath`:

```swift
enum Route: Hashable {
  case projectDetail(id: UUID)
  case settings
  case about
}

struct ContentView: View {
  @State var navigationPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navigationPath) {
      List(projects) { project in
        NavigationLink(value: Route.projectDetail(id: project.id)) {
          Text(project.name)
        }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .projectDetail(let id): ProjectDetailView(id: id)
        case .settings: SettingsView()
        case .about: AboutView()
        }
      }
    }
  }
}
```

## Performance optimisation

### LazyVStack / LazyHStack

Use for large collections — renders only visible rows:

```swift
ScrollView {
  LazyVStack(spacing: 0) {
    ForEach(largeList, id: \.id) { item in
      ItemRow(item: item)
    }
  }
}
```

### Stable identifiers in ForEach

Always `id: \.id`, not implicit integer index:

```swift
// Good
ForEach(items, id: \.id) { item in ItemView(item: item) }

// Bad — reorders cause wrong animations/state
ForEach(items, id: \.self) { item in ItemView(item: item) }
```

### Avoid expensive work in body

Move I/O and heavy computation into `.task {}`:

```swift
struct DetailView: View {
  @State var data: Data?

  var body: some View {
    VStack { Text(data?.name ?? "Loading...") }
    .task { data = await fetchData() }
  }
}
```

### Equatable conformance

Conform to `Equatable` and use `.equatable()` to skip re-renders when props are unchanged:

```swift
struct ExpensiveView: View, Equatable {
  let data: Data

  static func == (lhs: ExpensiveView, rhs: ExpensiveView) -> Bool {
    lhs.data.id == rhs.data.id
  }
}

ExpensiveView(data: data).equatable()
```

## Previews

```swift
#Preview {
  ProjectDetailView(
    project: Project(id: UUID(), name: "Sample Project", description: "A test project")
  )
}
```

## Anti-patterns

- **ObservableObject + @Published** — use `@Observable` instead
- **@StateObject** — use `@State` + `@Observable` instead
- **@EnvironmentObject** — use `@Environment` + Observable instead
- **AnyView type erasure** — use conditional view composition instead
- **Async work in body or init** — use `.task {}` or `.onAppear {}`
- **Creating view models in child views** — inject from parent
- **Ignoring Sendable** — `@MainActor`-annotated view models are Sendable automatically

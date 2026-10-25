# Human Interface Guidelines Checklist

Comprehensive checklist for iOS HIG compliance.

## iOS Human Interface Guidelines

### Layout & Spacing

#### Safe Areas

- [ ] Content respects safe area insets
- [ ] `.safeAreaInset()` used for persistent content
- [ ] `.ignoresSafeArea()` only for backgrounds/media

```swift
// ✅ Good
VStack {
    content
}
.safeAreaInset(edge: .bottom) {
    BottomBar()
}

// ✅ Good - Background extends
ZStack {
    Color.blue
        .ignoresSafeArea()
    content
}
```

#### Tap Targets

- [ ] Minimum 44x44 points for all interactive elements
- [ ] Adequate spacing between tappable elements

```swift
// ✅ Ensure minimum size
Button("Action") { }
    .frame(minWidth: 44, minHeight: 44)
```

#### Spacing

- [ ] Consistent spacing using system values
- [ ] `.padding()` for standard spacing
- [ ] `.padding(.horizontal)` / `.padding(.vertical)` for directional

```swift
// ✅ Use system spacing
VStack(spacing: 16) {
    // Standard spacing
}

// ✅ Use padding
content
    .padding()
```

#### ScrollView

- [ ] Long content uses ScrollView
- [ ] Scroll indicators visible
- [ ] Content offset considered

### Navigation

#### NavigationStack (iOS 16+)

- [ ] Use NavigationStack instead of deprecated NavigationView
- [ ] Proper navigation title placement
- [ ] Back button navigation works correctly

```swift
// ✅ Modern navigation
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) {
            ItemRow(item: item)
        }
    }
    .navigationTitle("Items")
    .navigationBarTitleDisplayMode(.large)
    .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
    }
}
```

#### Navigation Patterns

- [ ] Clear navigation hierarchy
- [ ] Proper use of navigation modifiers
- [ ] Toolbar items placed appropriately

```swift
// ✅ Toolbar placement
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("Add") { }
    }
}
```

### Modality

#### Sheets

- [ ] Sheets for focused tasks
- [ ] Dismiss gesture available
- [ ] Proper presentation detents on iOS 16+

```swift
// ✅ Proper sheet
.sheet(isPresented: $showingSheet) {
    AddItemView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

#### Alerts

- [ ] Destructive actions marked with role
- [ ] Cancel button provided
- [ ] Clear, concise messaging

```swift
// ✅ Proper alert
.alert("Delete Item?", isPresented: $showingAlert) {
    Button("Delete", role: .destructive) {
        deleteItem()
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This action cannot be undone.")
}
```

#### Confirmation Dialogs

- [ ] Use for multiple action choices
- [ ] Destructive actions at top
- [ ] Cancel at bottom

```swift
// ✅ Confirmation dialog
.confirmationDialog("Options", isPresented: $showingOptions) {
    Button("Delete", role: .destructive) { }
    Button("Archive") { }
    Button("Cancel", role: .cancel) { }
}
```

### Colors & Visuals

#### Semantic Colors

- [ ] Use semantic color names
- [ ] Avoid hardcoded colors
- [ ] Support both light and dark mode

```swift
// ✅ Semantic colors
.foregroundColor(.primary)      // Adapts to theme
.foregroundColor(.secondary)
.background(Color(.systemBackground))

// ❌ Hardcoded colors
.foregroundColor(.black)        // Doesn't adapt
.background(.white)
```

#### System Colors

- [ ] Use UIColor system colors via Color()
- [ ] Proper contrast in both modes

```swift
// ✅ System colors
Color(.systemRed)
Color(.systemBackground)
Color(.secondarySystemBackground)
Color(.label)
Color(.secondaryLabel)
```

#### Color Contrast

- [ ] Normal text: 4.5:1 minimum
- [ ] Large text (18pt+): 3.1 minimum
- [ ] UI components: 3:1 minimum
- [ ] Verify with Accessibility Inspector

#### SF Symbols

- [ ] Use SF Symbols for icons
- [ ] Consistent symbol style
- [ ] Proper symbol rendering mode

```swift
// ✅ SF Symbols
Image(systemName: "plus.circle.fill")
    .symbolRenderingMode(.hierarchical)
    .imageScale(.large)
```

### Lists & Collections

#### List Performance

- [ ] Use `id` for stable identities
- [ ] Provide IDs or use Identifiable
- [ ] Efficient row updates

```swift
// ✅ Stable IDs
List(items, id: \.id) { item in
    ItemRow(item: item)
}

// ✅ Or Identifiable
struct Item: Identifiable {
    let id: UUID
}

List(items) { item in
    ItemRow(item: item)
}
```

#### List Actions

- [ ] Swipe actions for common operations
- [ ] Context menus for additional actions
- [ ] Pull to refresh when appropriate

```swift
// ✅ Swipe actions
.swipeActions(edge: .trailing) {
    Button("Delete", role: .destructive) { }
}

// ✅ Context menu
.contextMenu {
    Button("Edit") { }
    Button("Delete", role: .destructive) { }
}
```

### Forms & Input

#### Form Structure

- [ ] Sections with headers
- [ ] Grouped related fields
- [ ] Clear labels

```swift
// ✅ Well-structured form
Form {
    Section("Basic Info") {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
    }

    Section("Preferences") {
        Toggle("Notifications", isOn: $notifications)
        Picker("Theme", selection: $theme) {
            ForEach(Theme.allCases) { theme in
                Text(theme.rawValue).tag(theme)
            }
        }
    }
}
```

#### Input Validation

- [ ] Real-time validation feedback
- [ ] Clear error messages
- [ ] Disable submit until valid

```swift
// ✅ Validation feedback
TextField("Email", text: $email)
    .textInputAutocapitalization(.never)
    .keyboardType(.emailAddress)
    .overlay(alignment: .trailing) {
        if !email.isEmpty && !isValidEmail {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
```

### Loading & Empty States

#### Loading States

- [ ] ProgressView for loading
- [ ] Descriptive labels
- [ ] Consider skeleton screens

```swift
// ✅ Loading state
if isLoading {
    ProgressView("Loading items...")
} else {
    ContentView()
}
```

#### Empty States

- [ ] Helpful message when empty
- [ ] Action to add first item
- [ ] Icon or illustration

```swift
// ✅ Empty state
if items.isEmpty {
    ContentUnavailableView(
        "No Items",
        systemImage: "tray.fill",
        description: Text("Add your first item to get started")
    )
} else {
    List(items) { item in
        ItemRow(item: item)
    }
}
```

#### Error States

- [ ] Clear error messaging
- [ ] Retry action
- [ ] Contact support option

```swift
// ✅ Error state
ContentUnavailableView(
    "Unable to Load",
    systemImage: "exclamationmark.triangle",
    description: Text("Please check your connection and try again")
) {
    Button("Retry") {
        loadData()
    }
}
```

## Testing Checklist

### Device Testing

- [ ] Test on smallest device
- [ ] Test on largest device
- [ ] Test on mid-size devices

### Orientation

- [ ] iPad: All orientations
- [ ] iPhone: Portrait and landscape
- [ ] Adaptive layouts

### Accessibility

- [ ] VoiceOver navigation
- [ ] Dynamic Type scaling
- [ ] Reduce Motion
- [ ] Increase Contrast

### Visual Modes

- [ ] Light mode
- [ ] Dark mode
- [ ] High contrast mode
- [ ] Reduce transparency

## References

- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- [Accessibility Guidelines](https://developer.apple.com/accessibility/)

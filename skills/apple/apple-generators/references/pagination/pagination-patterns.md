# Pagination Patterns and Best Practices

## Offset vs Cursor Pagination

### Offset-Based

```
GET /users?page=2&size=20
```

**Response:**

```json
{
  "items": [...],
  "totalItems": 150,
  "totalPages": 8,
  "currentPage": 2,
  "pageSize": 20
}
```

| Pros                  | Cons                                      |
| --------------------- | ----------------------------------------- |
| Simple to implement   | Inconsistent on inserts/deletes           |
| Jump to any page      | Slow on large datasets (SQL OFFSET)       |
| Know total count      | Duplicate/missing items when data changes |
| Easy "Page X of Y" UI |                                           |

**Best for:** Admin dashboards, search results, stable datasets.

### Cursor-Based

```
GET /users?cursor=eyJpZCI6MTAwfQ&limit=20
```

**Response:**

```json
{
  "items": [...],
  "nextCursor": "eyJpZCI6MTIwfQ",
  "hasMore": true
}
```

| Pros                           | Cons                          |
| ------------------------------ | ----------------------------- |
| Consistent with real-time data | Can't jump to arbitrary page  |
| Performant at any depth        | No total count (usually)      |
| No duplicates/gaps             | Opaque cursor (can't inspect) |
| Works with infinite scroll     |                               |

**Best for:** Social feeds, chat, real-time data, large datasets.

### Decision Guide

```
Is data frequently inserted/deleted?
├── Yes → Cursor-based
└── No
    ├── Need "jump to page N"? → Offset-based
    └── Infinite scroll only? → Either works, cursor preferred
```

## State Machine

Pagination has well-defined states. Model them explicitly:

```
                    ┌─────────┐
                    │  idle    │  (initial state)
                    └────┬────┘
                         │ loadFirstPage()
                    ┌────▼────┐
              ┌─────│ loading  │─────┐
              │     └─────────┘     │
          success              failure
              │                     │
        ┌─────▼─────┐      ┌───────▼──────┐
        │  loaded    │      │    error      │
        │ (has more) │      │ (retryable)   │
        └─────┬─────┘      └───────┬───────┘
              │ loadNextPage()     │ retry()
        ┌─────▼─────┐             │
        │  loading   │◄────────────┘
        │  (next)    │
        └─────┬─────┘
              │
        ┌─────▼──────┐
        │  exhausted  │  (no more pages)
        └────────────┘
```

### State Enum

```swift
enum PaginationState: Equatable {
    case idle
    case loading
    case loadingMore      // Loading subsequent pages (items already visible)
    case loaded
    case error(String)
    case exhausted        // All pages loaded, no more data
}
```

### Key State Rules

1. **idle → loading**: Only on first load
2. **loaded → loadingMore**: On subsequent pages (keeps existing items visible)
3. **error → loading/loadingMore**: On retry
4. **loaded → exhausted**: When response has fewer items than page size or `hasMore == false`
5. **Any → idle**: On refresh/reset

### Why "loadingMore" is Separate from "loading"

- `loading`: Show full-screen loading spinner, no items visible
- `loadingMore`: Show items + small bottom spinner, user can still scroll

## Threshold Prefetching

### The Problem

If you wait until the user scrolls to the very bottom to load the next page, they see a loading spinner every time. Bad UX.

### The Solution: Prefetch Threshold

Load the next page when the user is N items from the bottom:

```swift
func onItemAppear(_ item: Item) {
    let threshold = 5  // Load when 5 items from bottom
    guard let index = items.firstIndex(where: { $0.id == item.id }),
          index >= items.count - threshold else {
        return
    }
    Task { await loadNextPage() }
}
```

### Choosing a Threshold

| Page Size | Threshold | Why                             |
| --------- | --------- | ------------------------------- |
| 10        | 3         | Small pages load fast           |
| 20        | 5         | Standard                        |
| 50        | 10        | Large pages need more lead time |

Rule of thumb: threshold = pageSize / 4, minimum 3.

## Pull-to-Refresh

### Reset Everything on Refresh

```swift
func refresh() async {
    items.removeAll()
    currentPage = 0
    cursor = nil
    state = .idle
    await loadFirstPage()
}
```

### SwiftUI Integration

```swift
List {
    // ... items
}
.refreshable {
    await manager.refresh()
}
```

## Search + Pagination

### The Challenge

Search queries change pagination context:

- New query → reset to page 1
- Same query, scroll → load next page
- Empty query → show all (or clear)

### Debouncing

Don't fire API request on every keystroke:

```swift
@Observable
final class SearchablePaginationManager<Source: PaginatedDataSource> {
    var query: String = "" {
        didSet {
            debounceTask?.cancel()
            debounceTask = Task {
                try await Task.sleep(for: .milliseconds(300))
                await resetAndSearch()
            }
        }
    }

    private var debounceTask: Task<Void, Error>?

    private func resetAndSearch() async {
        pagination.reset()
        await pagination.loadFirstPage()
    }
}
```

### Cancel Previous Requests

When query changes, cancel in-flight requests:

```swift
func loadFirstPage() async {
    currentTask?.cancel()
    currentTask = Task {
        try Task.checkCancellation()
        let response = try await dataSource.fetch(query: query, page: firstPage)
        try Task.checkCancellation()  // Check again before updating UI
        self.items = response.items
    }
    try? await currentTask?.value
}
```

## Empty States

### What to Show

| State                  | What to Show                     |
| ---------------------- | -------------------------------- |
| `idle`                 | Nothing (or skeleton)            |
| `loading` (first page) | Full-screen spinner or skeleton  |
| `loadingMore`          | Items + bottom spinner           |
| `loaded` (0 items)     | Empty state illustration         |
| `error` (first page)   | Full-screen error with retry     |
| `error` (next page)    | Items + error banner + retry     |
| `exhausted`            | Items + "No more results" footer |

### ContentUnavailableView (iOS 17+)

```swift
if manager.items.isEmpty && manager.state == .loaded {
    ContentUnavailableView(
        "No Results",
        systemImage: "magnifyingglass",
        description: Text("Try a different search term")
    )
}
```

## Error Handling

### Retryable vs Non-Retryable

```swift
enum PaginationError: Error {
    case networkError(Error)    // Retryable
    case decodingError(Error)   // Usually not retryable
    case cancelled              // Not an error, ignore

    var isRetryable: Bool {
        switch self {
        case .networkError: return true
        case .decodingError: return false
        case .cancelled: return false
        }
    }
}
```

### Don't Lose Items on Error

```swift
// ❌ Wrong: clear items on next-page error
func loadNextPage() async {
    do {
        let response = try await fetch()
        items = response.items  // Replaces existing!
    } catch {
        items = []  // User loses everything
    }
}

// ✅ Right: keep existing items, show error for retry
func loadNextPage() async {
    do {
        let response = try await fetch()
        items.append(contentsOf: response.items)  // Append
    } catch {
        state = .error(error.localizedDescription)  // Items preserved
    }
}
```

## Performance Considerations

### Diffable Data

Use `Identifiable` items for efficient SwiftUI diffing:

```swift
protocol PaginatedDataSource {
    associatedtype Item: Identifiable & Sendable
    // ...
}
```

### Avoid Duplicate Requests

Guard against concurrent page loads:

```swift
func loadNextPage() async {
    guard state == .loaded else { return }  // Not idle, loading, or exhausted
    state = .loadingMore
    // ... fetch
}
```

### Memory Management for Large Lists

For lists with thousands of items, consider:

- LazyVStack (not List) for better memory behavior
- Limit in-memory items and reload from cache
- Use `.onDisappear` to release image data

## Anti-Patterns to Avoid

### Don't Use Array Index as Page Number

```swift
// ❌ Fragile — breaks if items are filtered or reordered
let page = items.count / pageSize

// ✅ Track page number explicitly
var currentPage = 0
```

### Don't Ignore Task Cancellation

```swift
// ❌ Stale response overwrites newer data
let response = try await fetch(page: 2)
self.items = response.items  // Page 3 response may have already arrived

// ✅ Check cancellation
let response = try await fetch(page: 2)
try Task.checkCancellation()
self.items.append(contentsOf: response.items)
```

### Don't Paginate on the Main Actor

```swift
// ❌ Blocks UI during fetch
@MainActor func loadNextPage() async {
    let data = try await URLSession.shared.data(from: url)  // Blocks UI
}

// ✅ Fetch off main, update on main
func loadNextPage() async {
    let response = try await dataSource.fetch(page: nextPage)
    await MainActor.run { items.append(contentsOf: response.items) }
}
```

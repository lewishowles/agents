# Concurrency patterns

## Parts

- [Actors and isolation](concurrency-patterns-actors-and-isolation.md) (upstream `actors-and-isolation.md`)
- [Concurrency internals](concurrency-patterns-concurrency-internals.md) (upstream `concurrency-internals.md`)
- [Continuations and bridging](concurrency-patterns-continuations-bridging.md) (upstream `continuations-bridging.md`)
- [Migration guide](concurrency-patterns-migration-guide.md) (upstream `migration-guide.md`)
- [Structured concurrency](concurrency-patterns-structured-concurrency.md) (upstream `structured-concurrency.md`)
- [Swift 6.2 concurrency](concurrency-patterns-swift62-concurrency.md) (upstream `swift62-concurrency.md`)

<a id="source-swift-concurrency-patterns-skill-md"></a>

## Source: `swift/concurrency-patterns/SKILL.md`

# Swift Concurrency Patterns

Comprehensive guide for Swift concurrency covering async/await, structured concurrency, actors, and the Swift 6.2 "Approachable Concurrency" features. Focuses on patterns that prevent data races and common mistakes that cause crashes.

## When This Skill Activates

- User has data race errors or actor isolation compiler errors
- User is migrating to Swift 6 strict concurrency
- User asks about async/await, actors, Sendable, TaskGroup, or MainActor
- User needs to bridge legacy completion-handler APIs to async/await
- User is working with Swift 6.2 features (@concurrent, isolated conformances)
- User has concurrency bugs (actor reentrancy, task cancellation, UI freezes)

## Decision Tree

```
What concurrency problem are you solving?
│
├─ Swift 6 compiler errors / migration
│  └─ migration-guide.md
│
├─ Swift 6.2 new features (@concurrent, isolated conformances)
│  └─ swift62-concurrency.md
│
├─ Running work in parallel (async let, TaskGroup)
│  └─ structured-concurrency.md
│
├─ Thread safety for shared mutable state
│  └─ actors-and-isolation.md
│
├─ Bridging old APIs (delegates, callbacks) to async/await
│  └─ continuations-bridging.md
│
├─ Hangs, slow parallelism, thread-pool problems, profiling
│  └─ concurrency-internals.md
│
└─ General async/await patterns
   └─ See macos/coding-best-practices/modern-concurrency.md for basics
```

## Quick Reference

| Pattern                      | When to Use                                           | Reference                                        |
| ---------------------------- | ----------------------------------------------------- | ------------------------------------------------ |
| `async let`                  | Fixed number of parallel operations                   | `concurrency-patterns-structured-concurrency.md` |
| `withTaskGroup`              | Dynamic number of parallel operations                 | `concurrency-patterns-structured-concurrency.md` |
| `withDiscardingTaskGroup`    | Fire-and-forget parallel operations                   | `concurrency-patterns-structured-concurrency.md` |
| `.task { }` modifier         | Load data when view appears                           | `concurrency-patterns-structured-concurrency.md` |
| `.task(id:)` modifier        | Re-load when a value changes                          | `concurrency-patterns-structured-concurrency.md` |
| `actor`                      | Shared mutable state protection                       | `concurrency-patterns-actors-and-isolation.md`   |
| `@MainActor`                 | UI-bound state and updates                            | `concurrency-patterns-actors-and-isolation.md`   |
| `@concurrent`                | Explicitly offload to background (6.2)                | `concurrency-patterns-swift62-concurrency.md`    |
| Isolated conformances        | `@MainActor` type conforming to protocol (6.2)        | `concurrency-patterns-swift62-concurrency.md`    |
| `withCheckedContinuation`    | Bridge callback API to async                          | `concurrency-patterns-continuations-bridging.md` |
| `AsyncStream`                | Bridge delegate/notification API to async sequence    | `concurrency-patterns-continuations-bridging.md` |
| `@TaskLocal`                 | Context (IDs, tracing) down the task tree             | `concurrency-patterns-structured-concurrency.md` |
| `Atomic` / `Mutex`           | Sendable wrappers for synchronous hot paths (Swift 6) | `concurrency-patterns-actors-and-isolation.md`   |
| Custom actor executors       | Bridge existing DispatchSerialQueue synchronization   | `concurrency-patterns-concurrency-internals.md`  |
| Swift Concurrency Instrument | Diagnose hangs, actor contention, continuation leaks  | `concurrency-patterns-concurrency-internals.md`  |
| Strict concurrency migration | Incremental Swift 6 adoption                          | `concurrency-patterns-migration-guide.md`        |

## Process

### 1. Identify the Problem

Read the user's code or error messages to determine:

- Is this a compiler error (strict concurrency) or a runtime issue (data race, crash)?
- What Swift version and concurrency checking level are they using?
- Are they migrating existing code or writing new code?

### 2. Load Relevant Reference Files

Based on the problem, read from this directory:

- `concurrency-patterns-swift62-concurrency.md` — Swift 6.2 approachable concurrency features, Apple's adoption doctrine, Swift 6.3/6.4 additions
- `concurrency-patterns-structured-concurrency.md` — async let, TaskGroup, .task modifier lifecycle, task-locals, cancellation semantics
- `concurrency-patterns-actors-and-isolation.md` — Actor patterns, reentrancy, @MainActor, Sendable, Atomic/Mutex
- `concurrency-patterns-concurrency-internals.md` — cooperative pool, unsafe primitives, actor scheduling, Swift Concurrency Instrument
- `concurrency-patterns-continuations-bridging.md` — withCheckedContinuation, AsyncStream, built-in async sequences, legacy bridging
- `concurrency-patterns-migration-guide.md` — Incremental Swift 6 strict concurrency adoption (WWDC24 doctrine)

### 3. Review Checklist

- [ ] No blocking calls on `@MainActor` (use `await` for long operations)
- [ ] Shared mutable state protected by an actor (not locks or DispatchQueue)
- [ ] `Sendable` conformance correct for types crossing isolation boundaries
- [ ] Task cancellation handled (check `Task.isCancelled` or `Task.checkCancellation()`)
- [ ] No unstructured `Task {}` where structured concurrency (`.task`, `TaskGroup`) would work
- [ ] Actor reentrancy considered at suspension points
- [ ] `withCheckedContinuation` called exactly once (not zero, not twice)
- [ ] `.task(id:)` used instead of manual `onChange` + cancel patterns

### 4. Cross-Reference

- For **async/await basics and actor fundamentals**, see `../macos/coding-best-practices-modern-concurrency.md`
- For **networking concurrency patterns**, see `../../../apple-generators/references/networking-layer/networking-patterns.md`
- For **SwiftData concurrency** (@ModelActor), see `../macos/swiftdata-architecture-repository-pattern.md`
- For **auth token refresh with actors**, see `../../../apple-generators/references/auth-flow/auth-patterns.md`

## References

- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [Migrating to Swift 6](https://www.swift.org/migration/documentation/migrationguide/)
- Local captured doc (optional): `~/Downloads/docs/Swift-Concurrency-Updates.md` — read if present; skip silently if absent.

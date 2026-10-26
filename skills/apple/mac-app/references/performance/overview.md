# Overview

## Parts

- [Profiling](profiling.md)
- [SwiftUI debugging](swiftui-debugging.md)

<a id="source-performance-skill-md"></a>

## Source: `performance/SKILL.md`

# Performance Skills

Diagnose and fix performance problems, from system-level profiling to SwiftUI render behavior.

## When This Skill Activates

Use this skill when the user:

- Reports the app is **slow, janky, or hanging**
- Wants to profile with **Instruments** (Time Profiler, Allocations, Hangs)
- Is investigating **memory issues, slow launches, or energy drain**
- Sees SwiftUI views **re-rendering too often** or slow `body` evaluations
- Asks about **view identity** problems or `_printChanges()`

## Available Skills

Paths are relative to THIS file's directory — skills run with cwd set to the
user's project, so resolve each path from this local reference page's location.

| Skill             | Read                   | Covers                                                              |
| ----------------- | ---------------------- | ------------------------------------------------------------------- |
| profiling         | `profiling.md`         | Instruments workflows; hangs, memory, slow launch, energy diagnosis |
| swiftui-debugging | `swiftui-debugging.md` | Unnecessary re-renders, view identity, slow body evaluations        |

## How to Route

1. Match the request to a row above — system-level symptoms → profiling; SwiftUI render symptoms → swiftui-debugging.
2. Read that local reference page (relative to this file) plus any reference files it lists.
3. Apply the guidance to the user's code.

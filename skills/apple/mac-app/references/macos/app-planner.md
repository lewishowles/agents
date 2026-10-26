# App planner

<a id="source-macos-app-planner-skill-md"></a>
## Source: `macos/app-planner/SKILL.md`

# App Planner for macOS

You are a macOS app architect specializing in project planning and analysis.

## When This Skill Activates

- User wants to plan a new macOS app
- User wants to analyze or audit an existing macOS project
- User asks to architect a macOS app
- User wants planning documents for their macOS app
- User asks to review project structure for a macOS app

## Your Role

Create comprehensive planning documents for new macOS apps or analyze existing projects.

## Core Functions

1. **New App Planning** - Create 8 planning documents for new projects
2. **Existing App Analysis** - Create 10 analysis documents for existing apps

## Module References

1. **New App Planning**: [New app planning](#source-macos-app-planner-new-app-planning-md)
2. **Existing App Analysis**: [Existing app analysis](#source-macos-app-planner-existing-app-analysis-md)

## Approach

- Ask detailed questions about requirements
- Plan for SOLID/DRY principles
- Consider accessibility and performance

Begin by asking whether this is a new app or existing app analysis.

<a id="source-macos-app-planner-existing-app-analysis-md"></a>
## Source: `macos/app-planner/existing-app-analysis.md`

# Existing macOS App Analysis

Create 10 comprehensive analysis documents for existing apps.

## 1. Current Architecture Audit

- Current tech stack
- Architecture pattern used
- Code organization
- Dependencies

## 2. Code Quality Assessment

- SOLID compliance
- DRY violations
- Code duplication
- Design patterns used

## 3. UI/UX Tahoe Compatibility

- Liquid Glass adoption
- HIG compliance
- macOS 26 features used
- Accessibility status

## 4. Data Layer Analysis

- Current persistence (Core Data, etc.)
- SwiftData migration potential
- Data model review

## 5. Performance Profiling

- Bottlenecks identified
- Memory usage
- Launch time
- Optimization opportunities

## 6. Accessibility Audit

- VoiceOver support
- Keyboard navigation
- Dynamic Type
- Color contrast

## 7. Security and Sandboxing

- Current entitlements
- Security vulnerabilities
- Sandbox compatibility

## 8. Dependency Analysis

- Third-party dependencies
- Version currency
- Security audits

## 9. Test Coverage Report

- Current test coverage
- Missing tests
- Quality metrics

## 10. Modernization Roadmap

- Intel → Apple Silicon
- Core Data → SwiftData
- Objective-C → Swift
- Liquid Glass adoption
- Priority timeline

<a id="source-macos-app-planner-new-app-planning-md"></a>
## Source: `macos/app-planner/new-app-planning.md`

# New macOS App Planning

Create 8 comprehensive planning documents for new macOS projects.

## 1. Feature Specification

- Core features list
- User stories
- Feature prioritization (MVP vs future)
- Target audience
- Success criteria

## 2. Architecture Decision

- SwiftUI vs AppKit vs Hybrid
- MVVM architecture
- Modular design approach
- SwiftData for persistence
- Dependency injection strategy

## 3. Data Model Design

- SwiftData models and relationships
- Schema design
- Migration strategy
- CloudKit sync (if needed)

## 4. UI/UX Wireframes

- Window structure
- Navigation pattern (sidebar, tabs)
- Liquid Glass design integration
- Accessibility considerations
- Responsive layouts

## 5. Technology Stack

- Swift 6
- SwiftUI/AppKit
- SwiftData
- Frameworks needed
- Third-party dependencies

## 6. Project Structure

- Feature-based modules
- Swift Package organization
- File structure
- Testing strategy

## 7. Testing Strategy

- Unit tests
- UI tests
- Integration tests
- Test coverage goals

## 8. Distribution Plan

- Mac App Store vs direct
- Code signing
- Notarization
- Update mechanism

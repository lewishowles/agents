# Sources and refresh

## Kept iOS skills

- Repository: https://github.com/rshankras/claude-code-apple-skills
- Pin: `5f1f5697c77adf99816de1a5c21742532a1c6f46` (30 June 2026)
- Licence: MIT, copyright (c) 2025 Ravishankar
- The local copy this skill was built from matched upstream exactly at this pin.

The table maps every local reference to exactly one upstream file. The reference
body keeps the upstream text apart from removed skill front matter and adapted
links. Filename pointers to other retained topics and to Mac app references became
relative Markdown links. The app planner's links to example files that it asks
an agent to create became code paths, because those files are not part of this skill.
The watchOS complications mention remains plain text. The formatter also realigned
tables, widened some code fences and escaped some characters; the wording is unchanged.

| Local file                                                                                                               | Upstream path                                        |
| ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| [`references/overview.md`](references/overview.md)                                                                       | `ios/SKILL.md`                                       |
| [`references/app-planner/overview.md`](references/app-planner/overview.md)                                               | `ios/app-planner/SKILL.md`                           |
| [`references/app-planner/architecture-guide.md`](references/app-planner/architecture-guide.md)                           | `ios/app-planner/architecture-guide.md`              |
| [`references/app-planner/planning-checklist.md`](references/app-planner/planning-checklist.md)                           | `ios/app-planner/planning-checklist.md`              |
| [`references/app-planner/tech-stack-options.md`](references/app-planner/tech-stack-options.md)                           | `ios/app-planner/tech-stack-options.md`              |
| [`references/assistive-access/overview.md`](references/assistive-access/overview.md)                                     | `ios/assistive-access/SKILL.md`                      |
| [`references/coding-best-practices/overview.md`](references/coding-best-practices/overview.md)                           | `ios/coding-best-practices/SKILL.md`                 |
| [`references/coding-best-practices/architecture-patterns.md`](references/coding-best-practices/architecture-patterns.md) | `ios/coding-best-practices/architecture-patterns.md` |
| [`references/coding-best-practices/coredata-patterns.md`](references/coding-best-practices/coredata-patterns.md)         | `ios/coding-best-practices/coredata-patterns.md`     |
| [`references/coding-best-practices/swift-patterns.md`](references/coding-best-practices/swift-patterns.md)               | `ios/coding-best-practices/swift-patterns.md`        |
| [`references/coding-best-practices/swiftui-patterns.md`](references/coding-best-practices/swiftui-patterns.md)           | `ios/coding-best-practices/swiftui-patterns.md`      |
| [`references/ipad-patterns/overview.md`](references/ipad-patterns/overview.md)                                           | `ios/ipad-patterns/SKILL.md`                         |
| [`references/ipad-patterns/drag-drop.md`](references/ipad-patterns/drag-drop.md)                                         | `ios/ipad-patterns/drag-drop.md`                     |
| [`references/ipad-patterns/input-methods.md`](references/ipad-patterns/input-methods.md)                                 | `ios/ipad-patterns/input-methods.md`                 |
| [`references/ipad-patterns/multitasking.md`](references/ipad-patterns/multitasking.md)                                   | `ios/ipad-patterns/multitasking.md`                  |
| [`references/migration-patterns/overview.md`](references/migration-patterns/overview.md)                                 | `ios/migration-patterns/SKILL.md`                    |
| [`references/migration-patterns/coredata-to-swiftdata.md`](references/migration-patterns/coredata-to-swiftdata.md)       | `ios/migration-patterns/coredata-to-swiftdata.md`    |
| [`references/migration-patterns/objc-to-swift.md`](references/migration-patterns/objc-to-swift.md)                       | `ios/migration-patterns/objc-to-swift.md`            |
| [`references/migration-patterns/observable-migration.md`](references/migration-patterns/observable-migration.md)         | `ios/migration-patterns/observable-migration.md`     |
| [`references/migration-patterns/storekit-migration.md`](references/migration-patterns/storekit-migration.md)             | `ios/migration-patterns/storekit-migration.md`       |
| [`references/migration-patterns/uikit-to-swiftui.md`](references/migration-patterns/uikit-to-swiftui.md)                 | `ios/migration-patterns/uikit-to-swiftui.md`         |
| [`references/migration-patterns/xctest-to-swift-testing.md`](references/migration-patterns/xctest-to-swift-testing.md)   | `ios/migration-patterns/xctest-to-swift-testing.md`  |
| [`references/navigation-patterns/overview.md`](references/navigation-patterns/overview.md)                               | `ios/navigation-patterns/SKILL.md`                   |
| [`references/navigation-patterns/navigation-split-view.md`](references/navigation-patterns/navigation-split-view.md)     | `ios/navigation-patterns/navigation-split-view.md`   |
| [`references/navigation-patterns/navigation-stack.md`](references/navigation-patterns/navigation-stack.md)               | `ios/navigation-patterns/navigation-stack.md`        |
| [`references/navigation-patterns/navigation-transitions.md`](references/navigation-patterns/navigation-transitions.md)   | `ios/navigation-patterns/navigation-transitions.md`  |
| [`references/navigation-patterns/programmatic-navigation.md`](references/navigation-patterns/programmatic-navigation.md) | `ios/navigation-patterns/programmatic-navigation.md` |
| [`references/navigation-patterns/tab-view.md`](references/navigation-patterns/tab-view.md)                               | `ios/navigation-patterns/tab-view.md`                |
| [`references/ui-review/overview.md`](references/ui-review/overview.md)                                                   | `ios/ui-review/SKILL.md`                             |
| [`references/ui-review/accessibility-quick-ref.md`](references/ui-review/accessibility-quick-ref.md)                     | `ios/ui-review/accessibility-quick-ref.md`           |
| [`references/ui-review/font-guidelines.md`](references/ui-review/font-guidelines.md)                                     | `ios/ui-review/font-guidelines.md`                   |
| [`references/ui-review/hig-checklist.md`](references/ui-review/hig-checklist.md)                                         | `ios/ui-review/hig-checklist.md`                     |

## Manual refresh

1. Fetch a chosen newer commit of the upstream repository and record its full hash.
2. Compare every mapped path with that commit, including renamed and removed files. Check changed API guidance against current Apple documentation and the project's deployment target.
3. Review changes for relevance, accuracy, licence terms and conflicts with the existing Apple, Swift and SwiftUI skills. Update affected references and the source map, then move the pin only after the whole source set has been reviewed.
4. Run repository validation and review the resulting diff before accepting the refresh. Keep upgrades separate from unrelated skill work.

## MIT licence: Ravishankar

MIT License

Copyright (c) 2025 Ravishankar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

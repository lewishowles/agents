# Sources and refresh

## Kept Apple skills

- Repository: https://github.com/rshankras/claude-code-apple-skills
- Pin: `9ffb83138209057875698dd11c1720c657c47a92` (24 July 2026)
- Licence: MIT, copyright (c) 2025 Ravishankar
- The table maps the 18 references and rules kept from the pinned upstream commit.

Each local file maps to one upstream file. File bodies keep the upstream text apart from removed front matter, the added Parts line in `references/core-ml/overview.md`, links and path pointers adapted to the local layout, formatter output, and platform and non-Swift exclusions.

Links to the retired `swift-ui` skill were changed to point at the merged `swift` skill.

| Local file                                                                                                                                             | Upstream path                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| [`references/apple-intelligence/app-intents-advanced-features.md`](references/apple-intelligence/app-intents-advanced-features.md)                     | `apple-intelligence/app-intents/advanced-features.md`           |
| [`references/apple-intelligence/app-intents-entities-spotlight.md`](references/apple-intelligence/app-intents-entities-spotlight.md)                   | `apple-intelligence/app-intents/entities-spotlight.md`          |
| [`references/apple-intelligence/app-intents-intents-basics.md`](references/apple-intelligence/app-intents-intents-basics.md)                           | `apple-intelligence/app-intents/intents-basics.md`              |
| [`references/apple-intelligence/app-intents.md`](references/apple-intelligence/app-intents.md)                                                         | `apple-intelligence/app-intents/SKILL.md`                       |
| [`references/apple-intelligence/foundation-models.md`](references/apple-intelligence/foundation-models.md)                                             | `apple-intelligence/foundation-models/SKILL.md`                 |
| [`references/apple-intelligence/foundation-models-models-and-agents.md`](references/apple-intelligence/foundation-models-models-and-agents.md)         | `apple-intelligence/foundation-models/models-and-agents.md`     |
| [`references/apple-intelligence/foundation-models-safety-and-guardrails.md`](references/apple-intelligence/foundation-models-safety-and-guardrails.md) | `apple-intelligence/foundation-models/safety-and-guardrails.md` |
| [`references/apple-intelligence/foundation-models-utilities-package.md`](references/apple-intelligence/foundation-models-utilities-package.md)         | `apple-intelligence/foundation-models/utilities-package.md`     |
| [`references/apple-intelligence/overview.md`](references/apple-intelligence/overview.md)                                                               | `apple-intelligence/SKILL.md`                                   |
| [`references/apple-intelligence/visual-intelligence.md`](references/apple-intelligence/visual-intelligence.md)                                         | `apple-intelligence/visual-intelligence/SKILL.md`               |
| [`references/core-ml/overview.md`](references/core-ml/overview.md)                                                                                     | `core-ml/SKILL.md`                                              |
| [`references/core-ml/patterns.md`](references/core-ml/patterns.md)                                                                                     | `core-ml/patterns.md`                                           |
| [`references/core-ml/templates.md`](references/core-ml/templates.md)                                                                                   | `core-ml/templates.md`                                          |
| [`references/mapkit/geotoolbox.md`](references/mapkit/geotoolbox.md)                                                                                   | `mapkit/geotoolbox/SKILL.md`                                    |
| [`references/mapkit/overview.md`](references/mapkit/overview.md)                                                                                       | `mapkit/SKILL.md`                                               |
| [`references/security/overview.md`](references/security/overview.md)                                                                                   | `security/SKILL.md`                                             |
| [`references/security/privacy-manifests.md`](references/security/privacy-manifests.md)                                                                 | `security/privacy-manifests/SKILL.md`                           |
| [`references/security/rules/swiftlint.yml`](references/security/rules/swiftlint.yml)                                                                   | `security/rules/swiftlint.yml`                                  |

## Removed upstream security references

Upstream removed `security/biometric-auth.md`, `security/network-security.md`, `security/platform-specifics.md` and `security/secure-storage.md` in commit `098c1b4` after its July 2026 blind-test audit judged that current models already know the material. There was no replacement upstream. The local copies were removed to follow upstream; recover them from the previous pin, `5f1f5697c77adf99816de1a5c21742532a1c6f46`, if the guidance is needed again.

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

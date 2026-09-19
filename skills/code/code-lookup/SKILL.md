---
name: code-lookup
description: >
  Use this skill when locating code, tracing behaviour, or choosing between Serena, codebase-memory, and text search.
filePatterns: []
pathPatterns: []
---
# Code lookup

Choose one primary lookup tool for the question. The failure this prevents is calling multiple overlapping analysers before the first tool has shown it is insufficient.

## Routing

| Question                                                                                                   | Start with                   |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Exact symbol, definition, references, diagnostics, or semantic edit                                        | Serena                       |
| Broad architecture, multi-hop impact, cross-service, cross-repository, or language-agnostic graph question | codebase-memory              |
| Literal string, configuration value, documentation line, generated asset, or named non-code file           | Targeted text or file lookup |

Read only the reference for the selected tool:

- Serena: [references/serena.md](references/serena.md)
- codebase-memory: [references/codebase-memory.md](references/codebase-memory.md)

## Workflow

1. Classify the question using the routing table.
2. Use the selected tool before broad shell searches or loading another analyser.
3. Stop discovery once the exact file, symbol, relationship, or finding is known.
4. Add a second tool only when the first result identifies a distinct next job.

Valid hand-offs include:

- codebase-memory maps a broad impact surface, then Serena performs a reference-aware edit
- A targeted text search identifies a config entry, then no structural tool is needed

Do not call Serena and codebase-memory merely to compare answers. Do not use codebase-memory as a mandatory first step.

## Fallbacks

- If the selected tool is unavailable, state that once and use the narrowest suitable local alternative.
- If an index or analysis is stale, refresh that tool rather than silently switching tools.
- If the task concerns live behaviour, reproduce or diagnose it. Repository lookup cannot prove runtime state.

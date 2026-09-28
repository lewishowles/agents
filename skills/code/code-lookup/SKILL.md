---
name: code-lookup
description: >
  Use this skill when locating code, tracing behaviour, choosing between codebase-memory and text search, or when a guard hook blocks a search or file read.
---
# Code lookup

Choose one primary lookup tool for the question. The failure this prevents is calling multiple overlapping analysers before the first tool has shown it is insufficient.

## Routing

| Question                                                                                                   | Start with                                    |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Where a known symbol is defined or used, or every place a rename must touch                                | Scoped `rg -w` for the name, then read ranges |
| Broad architecture, multi-hop impact, cross-service, cross-repository, or language-agnostic graph question | codebase-memory                               |
| Type errors or broken references after a change                                                            | The project's typecheck or lint command       |
| Literal string, configuration value, documentation line, generated asset, or named non-code file           | Targeted text or file lookup                  |

For codebase-memory, read [references/codebase-memory.md](references/codebase-memory.md).

## Workflow

1. Classify the question using the routing table.
2. Use the selected tool before broad shell searches or loading another analyser.
3. Stop discovery once the exact file, symbol, relationship, or finding is known. For an edit, use the narrowest source snippet or patch anchor needed; search again only to verify the changed reference.
4. Add a second tool only when the first result identifies a distinct next job.

Valid hand-offs include:

- codebase-memory maps a broad impact surface, then a scoped `rg -w` lists the exact lines to patch, and the project's typecheck confirms nothing was missed
- A targeted text search identifies a config entry, then no structural tool is needed

Do not call codebase-memory and a text search merely to compare answers. Do not use codebase-memory as a mandatory first step.

After a guard hook blocks several searches or reads in a row, use one codebase-memory lookup, known-symbol read, or single targeted file range, then reassess before another search or read. Project guard hooks take precedence over advice to parallelise file reads.

## Fallbacks

- If the selected tool is not visible, look it up by name with the harness's tool discovery first. If it is still unavailable, state that once and use the narrowest suitable local alternative.
- If an index or analysis is stale, refresh that tool rather than silently switching tools.
- If the task concerns live behaviour, reproduce or diagnose it. Repository lookup cannot prove runtime state.

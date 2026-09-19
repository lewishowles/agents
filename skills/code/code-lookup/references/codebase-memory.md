# Codebase-memory

Use codebase-memory for questions that need a persistent, language-agnostic graph:

- broad architecture and package relationships
- multi-hop callers, callees, and impact surfaces
- HTTP, asynchronous, data-flow, and cross-service paths
- cross-repository relationships
- graph queries that combine several structural constraints

## Workflow

1. Use `list_projects` to find the indexed project.
2. Check `index_status`; index or refresh the repository when no usable graph exists.
3. Use `search_graph` to find exact graph entities.
4. Use `trace_path` for callers, callees, data flow, or cross-service paths.
5. Use `get_code_snippet` only after identifying the exact qualified name.
6. Use `query_graph` for relationships that simpler tools cannot express.
7. Use `detect_changes` when the question concerns the structural impact of local changes.

Do not use the graph for literal strings, configuration, documentation, generated assets, or a single exact symbol that Serena can answer directly. Graph results are analysis, not semantic edits. Hand a concrete symbol to Serena when a reference-aware change is required.

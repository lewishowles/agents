## File discovery

Minimise token cost while discovering files; answer the narrow question with the smallest output.

- Prefer `rg` and `rg --files`, scoped to the smallest likely directory (`rg --files src`, not a repo-wide scan). Plain `rg` already honours `.gitignore` and skips `node_modules`, `dist`, and caches, which is what you want by default.
- When you specifically need files that `.gitignore` hides, add `--no-ignore` (or `include_gitignored: true` for the Glob/Grep tools) and keep the path scoped to a named directory. A broad `rg --no-ignore`, `grep -r`, or `find` targeting `.`, `~`, `/`, or a protected directory is blocked by `guard-search-boundaries`; scope the path or use the Grep/Glob tools instead.
- Do not inspect generated, vendored, cached, build, dependency, or large binary directories unless explicitly asked: `node_modules`, `dist`, `build`, `.git`, coverage, caches, generated plugin bundles, lockfile-heavy generated output, local secrets.
- Do not use broad `find`, `ls -R`, or unscoped glob searches. If `find` is unavoidable, scope it to named directories and group `-o` expressions with parentheses.
- If a task packet, handoff, or the user's message already names the exact target file(s), symbol, or finding, skip indexing and search entirely and read the named location directly. Only search when the target is genuinely unknown or the handoff is incomplete.
- After making file edits, do not self-review by reading several changed files in sequence. Prefer diagnostics, formatter output, targeted symbol lookup, or a single patch-anchor read only when needed.
- For build artefact checks, inspect the exact expected output path rather than listing whole build trees.
- If a command unexpectedly starts dumping large output, stop using that pattern and switch to a narrower command.
- If a user says a file exists and a search cannot find it, re-run with `--no-ignore` before concluding it is missing, then say whether gitignored files were included.
- Never rely on a remembered line number to offset-read into a file. Formatters shift lines on save. Use `rg -n 'pattern' file` to find the current line first, then read from that offset.
- Never use a `&&` chain to conclude a file exists or is absent. A `&&` exits non-zero silently on any failure in the chain, not just a missing file. Use the Read tool or an explicit `[[ -f path ]]` check with a verified exit status instead.

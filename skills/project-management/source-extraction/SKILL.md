---
name: source-extraction
description: >
  Use this skill when asked to extract raw material from an external page or artefact — for another agent to run, or before feeding the result into project-learn-from-source — without summarising away meaning.
---
# Source extraction

Extracting a page for later analysis is not the same task as summarising it for a human. The failure this skill prevents: a "summary" pass quietly drops the caveats, config, and dependent links that a downstream analysis (like `project-learn-from-source`) actually needs, and by the time that's discovered the meaning is already gone. The full extraction stays in a temporary file; the learner receives an index first and requests only the excerpts it needs.

## Scope

Use when asked to:

- prepare a page, article, or artefact for another agent (including a non-Claude tool such as ChatGPT) to extract before analysis
- reduce token cost of reading several sources before running `project-learn-from-source`
- turn a long external page into structured raw material without losing anything load-bearing

Do not use this skill to:

- write a summary meant for a human to read directly, which is lossy by design
- perform the actual repository judgement, which belongs to `project-learn-from-source`
- review this repo's own files or commits, see `project-review-worktree` or `project-review-commits`

## Method

Extraction, not summarisation: preserve every claim, constraint, and example fully rather than compressing. Don't expect verbatim reproduction, so restate everything fully and precisely in your own words. Quote exact phrases only where wording itself matters (named rules, specific caveats), nothing dropped or compressed.

The extraction is a lossless evidence handoff, not an opinion pass. Do not rank, judge, or classify claims, examples, or their local value. You may describe the source's own headings, stated priorities, and explicit caveats, but do not interpret them for the current repository.

Before acquiring the source, create a scratch directory with `mktemp -d` outside the repository. Write the complete structured extraction to a file in that directory. Keep the file available for excerpt requests for the rest of the handoff.

Return only this receipt to the requester, never the full extraction:

```markdown
Extraction receipt
- Scratch path: <absolute path outside the repository>
- Source identity: <URL or file, title, author or organisation, and date when available>
- Index:
  1. <one-line claim or concrete example, with enough wording to identify the full entry>
  2. <one-line claim or concrete example>
```

Number every claim and concrete example in the index. Keep identifiers stable, and include any caveat or constraint whose absence could make the learner request the wrong excerpt. The index is a locator, not a summary or judgement.

Write the full extraction to the scratch file using this structure:

```markdown
## Source
<URL, title, author or organisation if present, date if present>

## Claims and statements
- Full, precise restatement of any concrete claim, recommendation, rule, or pattern, with enough surrounding context to stand alone. Quote a short exact phrase only where the wording itself is the point.

## Config, code, or examples
- Any code snippets, config, commands, or worked examples, reproduced exactly, with a one-line note of what each is for.

## Constraints and caveats
- Stated conditions, exceptions, prerequisites, versions, or "this only applies when..." qualifiers.

## Structure and priorities
- What the page explicitly emphasises through headings, repetition, or stated "most important" framing. Describe the source's structure only, without judging its importance for the current repository.

## Referenced links worth reviewing separately
- Incidental or further reading: <anchor text, destination URL (or "destination not resolvable"), one-line why>

## Linked artefacts the article depends on
- Links where the article is describing, demonstrating, or quoting from the linked repo, download, or doc itself. <anchor text, destination URL (or "destination not resolvable"), one-line on what it is>

## Excluded
- Boilerplate skipped (nav, ads, cookie banners, unrelated sidebar content), so it's clear nothing substantive was silently dropped.
```

Do not shorten, generalise, rank, judge, or classify the extracted material. Completeness of meaning over concision or exact wording. This file feeds a separate analysis step, not a human reader.

## Acquire the source

Choose the acquisition path from the URL before reading the source:

- For `github.com`, `raw.githubusercontent.com`, or `gist.github.com` file or blob URLs that point to one file, fetch the raw file content directly: rewrite a `github.com/.../blob/...` URL to its `raw.githubusercontent.com` equivalent, rewrite a `gist.github.com` URL to its `gist.githubusercontent.com/.../raw/...` equivalent, or use `gh api -H "Accept: application/vnd.github.raw" repos/:owner/:repo/contents/:path` (plain `gh api` without that header returns base64-encoded JSON, not the file content). Do not render the HTML page.
- For a GitHub repository root or a URL that needs multi-file exploration, use `gh repo clone --depth 1` (or `git archive`) in a scratch directory. Read only the targeted files with normal Read or `rg` tools. Do not render GitHub pages.
- For every other URL, first check `command -v page-to-markdown`. When available, use `page-to-markdown` to convert the page to compact Markdown before reading it. When unavailable, use WebFetch, condense the result manually, and say in the report that `page-to-markdown` was unavailable.

## Handing this to another agent

If the extraction will run in a tool without repo or conversation context (for example, pasted into ChatGPT):

1. Give it the method and output shape above as its instructions, then the URL.
2. It must not fetch or follow links itself. Links are noted, not chased. Auto-recursion turns one URL into an unbounded, unpredictable amount of work.
3. If the tool has no filesystem access, return the full structured output to the invoking agent. The invoking agent writes it to a `mktemp` scratch directory outside the repository, then sends the learner only the receipt and source URL. A delegated fork or subagent with filesystem access may perform the scratch write itself. The learner can request numbered excerpts from the extraction worker.

## Multiple sources

Don't paste many URLs into one analysis pass. Synthesis over a large corpus surfaces only top ideas and drops the rest. Instead:

- Extract each source separately
- Feed each receipt into `project-learn-from-source`, then request only the relevant excerpts in small batches

## After extraction

If "linked artefacts the article depends on" has entries, record them in the full extraction and let the learner request them if they are load-bearing. Once extraction is done, hand the receipt to `project-learn-from-source`. The learner requests indexed excerpts and owns every repository judgement and trade-off.

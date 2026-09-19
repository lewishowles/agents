---
name: writing-readme
description: >
  Use this skill when writing or editing a README file (README.md or similar). Covers what belongs in a README, what doesn't, structure, and the "no fluff that doesn't help the average reader" principle. Pair with the writing skill for voice and tone baselines.
filePatterns: [README.md]
pathPatterns: []
---
# README

README job: help someone who just landed — what it is, why it exists, how to use it. Quick-start guide, not marketing page.

## What belongs

- **Purpose** — one or two sentences: what this is, who it's for
- **Setup / install** — copyable steps. macOS-only? Say once. No fake Windows alternatives
- **Usage** — most common one or two uses, with examples
- **Where to look next** — links to deeper docs, contributing guide, license

## What doesn't belong

- Marketing prose, origin stories, repeated value-prop sentences
- Step-by-step for unsupported platforms
- Long feature lists — link to dedicated docs file instead
- Internal notes (decisions, history, TODOs) — use commits, ADRs, or project docs

## Tone

- Friendly, conversational, second-person ("you'll need…")
- Short steps and concrete commands; no preamble
- Sentence-case headings (`## Getting started`, not `## Getting Started`)
- UK spelling

## Before publishing

- Can a new reader run setup from a clean machine using only this?
- Platform assumptions stated explicitly?
- Cut anything that doesn't help the average reader

## Minimal structure

````markdown
# Project name

One or two sentences: what this is and who it's for.

## Requirements

- macOS
- Bun

## Getting started

```bash
bun install
bun run dev
```

## Usage

The most common command or workflow, with one short example.

## More information

- [Detailed docs](docs/)
````

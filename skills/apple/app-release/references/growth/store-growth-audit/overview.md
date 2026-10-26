# Store Growth Audit

Walk an app — new or live — through the full App Store growth playbook, phase by phase, and
produce a scorecard: what's installed, what's missing, what to do next, and who fixes it.

> The invariant: **every item has a detection rule**. Status comes from an ASC read, a codebase
> check, or an explicit question — never from vibes. If the user doesn't know, the item is
> 🟠 _unverified_, not assumed ✅.

## Where it fits (read the seams)

- **Not `store-signals`.** That is the continuous _signal → backlog_ loop: are the numbers moving,
  did last cycle's bets pay off? This is the _structural_ audit: is the machinery even installed?
  Run this quarterly (or pre-launch); run store-signals monthly. Trend questions route there.
- **Not `analytics-interpretation`.** Metric-quality judgments ("is 3.2% conversion good?") route
  there; this skill only records the baseline and whether benchmarks were checked.
- **Fixes never happen here.** Every 🔴/🟠 routes to a named sibling skill. This skill detects, scores, and routes. Read-only on ASC.

## When This Skill Activates

- "Audit my app's growth / store presence / what levers am I missing"
- A new app is approaching first submission and needs a growth plan, not just metadata
- Quarterly re-audit cadence, or after a launch that undershot expectations
- Before deciding to spend on paid acquisition ("is the free machinery done first?")
- Portfolio triage: "which of my apps is leaving the most on the table"

## The Model: P0–P9

54 items across ten phases. Each phase is a theme; the item detail lives in the checklist files.

| Phase | Theme                      | Items | Goal                                                                  |
| ----- | -------------------------- | ----- | --------------------------------------------------------------------- |
| P0    | Day-one money toggles      | 4     | Free margin + a measurement baseline before anything else             |
| P1    | On-metadata ASO            | 7     | Every indexed field working (title, subtitle, keywords, events, IAPs) |
| P2    | Conversion assets          | 5     | Icon, screenshots, trust signals that convert impressions             |
| P3    | Localization               | 5     | Metadata-first market expansion + PPP pricing                         |
| P4    | Ratings machinery          | 4     | Prompting, replying, and protecting the rating                        |
| P5    | Experimentation            | 4     | PPO, CPPs, events as a testing habit                                  |
| P6    | Featuring & free discovery | 6     | Nominations, new-OS adoption, storefronts, web presence               |
| P7    | Paid & external traffic    | 8     | Apple Ads ladder, launch spikes, pre-orders, codes                    |
| P8    | Earnings                   | 7     | Paywall experiments, win-backs, web checkout, bundles                 |
| P9    | Retention loop & ops       | 4     | Retention surfaces + the recurring refresh calendar                   |

**Compressed priority** (used for action selection, not the maturity ladder): P0 money toggles
first → P1–P3 (metadata, conversion, localization) → P8.4 web checkout + P8.6 volume purchasing
(the 2026-era revenue unlocks) → everything else → P7 paid traffic last. Paid spend on top of
broken free machinery is burned money.

## Reference Files

| File                                                   | Purpose                                                                                               |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| [`detection-playbook.md`](detection-playbook.md)       | Gather-once machinery: the MCP batch table, the codebase grep table, the single MANUAL question batch |
| [`audit-checklist-p0-p4.md`](audit-checklist-p0-p4.md) | Items P0.1–P4.4 (25): foundations — money toggles through ratings                                     |
| [`audit-checklist-p5-p9.md`](audit-checklist-p5-p9.md) | Items P5.1–P9.4 (29): growth loops — experimentation through ops                                      |

## Audit Process

1. **Resolve app, mode, and scope.** Get the `appId` (from `.planning/STATE.md` when present, else
   `list_apps` + confirm with the user). App live on the store → _existing_ mode;
   not yet shipped → _pre-launch_ mode. Scope defaults to the full P0–P9; a named phase runs
   scoped (see **Scoped Runs**). A prior scorecard (`GROWTH.md`), if present, is the diff baseline.
2. **Gather evidence — one pass, per [`detection-playbook.md`](detection-playbook.md).** Run the full MCP read batch, the
   full codebase grep pass, and ONE batched AskUserQuestion round for every MANUAL item. Never
   interleave gathering with scoring; never ask questions one at a time.
3. **Score all 54 items** against the gathered evidence using each item's `rule:`. Honor
   `applies-if:` guards (⚪ N/A) and ⏳ ANNOUNCED flags. Every status carries a terse, citable
   evidence string (`locales: en-US only`, `SBP: enrolled (user, 2026-07)`).
4. **Compute phase scores + maturity level** (rules below), and — when a prior scorecard exists —
   per-item deltas: fixed / regressed / new since last audit.
5. **Select the top 5 actions** (rule below).
6. **Write or refresh the scorecard** — in a project with `.planning/` this is `.planning/GROWTH.md`;
   standalone, write `GROWTH.md` beside the audit.
   Append an audit-history row; refresh the recurring calendar's next-due dates.
7. **Print the digest and route.** Maturity level, phase bar, top-5 with routes, deltas,
   unanswered MANUAL items, next three calendar due-dates, and the suggested next reference.

## Item Record Format

Each checklist item is a stanza:

```markdown
#### P3.1 Metadata-only localization (ja de fr es pt ko zh-Hans) — core
- detect: MCP `list_locales`
- rule: ✅ ≥7 target locales localized · 🟠 1–6 non-English locales · 🔴 en-only
- new-app: plan — seed target locales in the first submission
- fix: product/localization-strategy
```

- **ID** (`P<phase>.<n>`) is stable forever — scorecards diff by ID; never renumber.
- **Flags** after the name: `core` (phase-gating), `RECURRING` (calendar-driven), `⏳ ANNOUNCED (WWDC26)`.
- **detect:** `MCP <tool>` · `CODE <grep>` · `MANUAL <question>` · `HYBRID` (combination).
- **rule:** explicit ✅/🟠/🔴 thresholds; optional `applies-if:` guard → ⚪ N/A when it fails.
- **new-app:** how pre-launch mode scores it — `plan` / `code` / `defer` (see Modes).
- **fix:** `sibling-skill` — the named reference gives the next action.

**Status vocabulary:** ✅ done/healthy · 🟠 partial, stale, or unverified · 🔴 missing ·
⚪ N/A (applies-if failed; excluded from denominators) · ⏳ ANNOUNCED (not yet scoreable; excluded
from denominators; carries `prep:` and `recheck:` lines instead of a live rule).

## Scoring & Maturity

- **Phase score:** `✅ n / N applicable` — ⚪ and ⏳ items are excluded from N.
- **Phase grade:**
  - `Complete` — all applicable items ✅
  - `Working` — ≥50% ✅ **and no `core` item 🔴**
  - `Gaps` — any `core` item 🔴, or <50% ✅
  - `Not started` — no applicable item ✅
- **`core` items (13):** P0.1, P0.2, P1.1, P2.2, P2.4, P3.1, P4.1, P4.2, P5.1, P6.1, P8.1, P8.4, P9.2.
- **Growth maturity level (0–9):** the highest P such that every phase ≤ P grades at least
  `Working`. An app with P0–P3 working but P4 in gaps is Level 3, no matter how good P5–P9 look.
  The ladder follows numeric phase order; the compressed priority shapes only action selection.

**Top-5 action selection:** from all applicable 🔴 + 🟠 items, order by compressed-priority tier
(T1: P0 · T2: P1–P3 · T3: P8.4 + P8.6-when-live · T4: P4–P6, rest of P8, P9 · T5: P7), then within
a tier: `core` first, 🔴 before 🟠, lowest effort first. Two overrides: an **overdue RECURRING**
calendar item jumps to the top; always include at least one metadata-only quick win (shippable
without a binary release).

## Modes: Existing vs Pre-Launch

|                        | Existing app                  | Pre-launch                                                       |
| ---------------------- | ----------------------------- | ---------------------------------------------------------------- |
| Evidence               | ASC reads + codebase + MANUAL | `.planning/` docs + codebase + MANUAL                            |
| `new-app: plan` items  | scored normally               | planned-in-docs → 🟠 `planned`; absent → 🔴                      |
| `new-app: code` items  | scored normally               | scored normally (greps work pre-launch)                          |
| `new-app: defer` items | scored normally               | ⚪ with an activation trigger noted (e.g. "30 days post-launch") |
| Output framing         | audit + deltas                | launch plan (history row tagged `mode: pre-launch`)              |

The first post-launch audit diffs cleanly against the pre-launch scorecard — same IDs, same schema.

## Scoped Runs (single phase)

"Run phase 3" = audit + worklist for that stage only.

- **Scope**: one phase (`P3`, bare `3` accepted) or a short range/list (`P1-P3`, `P0,P4`).
  Default remains the full P0–P9 audit.
- **Evidence**: pull only the [`detection-playbook.md`](detection-playbook.md) rows whose items are in scope — MCP calls,
  greps, and MANUAL questions alike. A P1 run needs `get_metadata`/`list_locales`/`list_iap`/
  `list_app_events`, not sales reports or paywall greps.
- **Scorecard**: update only the in-scope phase tables and their Phase Scores rows; every other
  row stays untouched (stable IDs make the partial update safe). Append an Audit History row
  tagged `scope: P3`. Recompute the maturity level from the refreshed rows plus the untouched
  remainder — mark it `(est.)` if any out-of-scope phase has never been audited.
- **Output**: instead of the top-5, print the **phase worklist** — every applicable in-scope item
  with status, evidence, and route — ordered `core` first, 🔴 before 🟠, lowest effort first.
  End by offering to start the first route (gated, as always).
- A scoped run never rewrites items outside its scope, and never counts as a full re-audit for
  the Recurring Calendar's "announced-features recheck" row unless the ⏳ items are in scope.

## Output Format

The scorecard file:
header (app, date, mode, maturity) · phase-score table · top-5 actions · ten per-phase tables
(`ID | Item | Status | Evidence | Next step | Route`) · Watchlist (⏳ announced) · Recurring
Calendar · Baseline Metrics Snapshot · append-only Audit History.

The printed digest never dumps 54 rows:

```
Growth audit: <App> — Level 4/9 (existing, re-audit)
P0 ▓▓▓░ 3/4 · P1 ▓▓▓▓▓░░ 5/7 · P2 ▓▓▓░░ 3/5 · P3 ▓░░░░ 1/5 · P4 ▓▓▓▓ 4/4 …
Top 5: 1) P0.1 Apply to Small Business Program (route: growth/indie-business) …
Since last audit: 3 fixed, 1 regressed (P9.3 update freshness)
Unverified (you were unsure): P0.3 peer benchmarks, P7.2 brand defense
Calendar: featuring nomination due in 12 days · keyword refresh due 2026-10-01
Next: product/localization-strategy
```

## Routing Map

The only place the full route list lives; stanzas carry the short form.

| Audit area                                  | Related guidance                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SBP, business ops                           | [`growth/indie-business`](../indie-business/overview.md); App Store Connect enrolment is manual                                                                                                                                                                                                                                                                                                                                                      |
| Billing grace/retry, subscription lifecycle | [`generators/subscription-lifecycle`](../../../../apple-generators/references/subscription-lifecycle/overview.md)                                                                                                                                                                                                                                                                                                                                    |
| Analytics baseline, benchmarks              | [`growth/analytics-interpretation`](../analytics-interpretation/overview.md)                                                                                                                                                                                                                                                                                                                                                                         |
| Keywords, metadata fields, AI tagging       | [`app-store/keyword-optimizer`](../../app-store/keyword-optimizer/overview.md)                                                                                                                                                                                                                                                                                                                                                                       |
| Apple Ads (discovery, exact, halo, brand)   | [`app-store/apple-search-ads`](../../app-store/apple-search-ads/overview.md)                                                                                                                                                                                                                                                                                                                                                                         |
| Screenshots, previews, Creative Assets      | [`app-store/screenshot-planner`](../../app-store/screenshot-planner/overview.md)                                                                                                                                                                                                                                                                                                                                                                     |
| Icon + PPO + CPP experiments                | [`generators/product-page-optimization`](../../generators/product-page-optimization/overview.md), [`generators/custom-product-pages`](../../generators/custom-product-pages/overview.md)                                                                                                                                                                                                                                                             |
| In-app events                               | [`generators/in-app-events`](../../generators/in-app-events/overview.md)                                                                                                                                                                                                                                                                                                                                                                             |
| Localization + PPP pricing                  | [`product/localization-strategy`](../../product/localization-strategy/overview.md), [`monetization`](../../monetization/overview.md) (pricing-models)                                                                                                                                                                                                                                                                                                |
| Ratings: prompting, replies, protection     | [`app-store/ratings-mechanics`](../../app-store/ratings-mechanics/overview.md), [`generators/review-prompt`](../../../../apple-generators/references/review-prompt/overview.md), [`app-store/review-response-writer`](../../app-store/review-response-writer/overview.md)                                                                                                                                                                            |
| Featuring nominations                       | [`generators/featuring-nomination`](../../generators/featuring-nomination/overview.md); App Store Connect submission is manual                                                                                                                                                                                                                                                                                                                       |
| New-OS adoption                             | [Mac design](../../../../mac-app/references/design/overview.md) and [iPhone app guidance](../../../../iphone-app/SKILL.md)                                                                                                                                                                                                                                                                                                                           |
| App Intents / Spotlight                     | [`apple-intelligence/app-intents`](../../../../apple-frameworks/references/apple-intelligence/app-intents.md), [`generators/spotlight-indexing`](../../../../apple-generators/references/spotlight-indexing/overview.md)                                                                                                                                                                                                                             |
| Web SEO, landing page, deal sites           | [`app-store/web-presence`](../../app-store/web-presence/overview.md)                                                                                                                                                                                                                                                                                                                                                                                 |
| Pre-orders, offer codes, waitlist           | [`generators/pre-orders`](../../generators/pre-orders/overview.md), [`generators/offer-codes-setup`](../../generators/offer-codes-setup/overview.md), [`product/beta-testing`](../../product/beta-testing/overview.md)                                                                                                                                                                                                                               |
| Paywall + pricing experiments               | [`generators/paywall-generator`](../../../../apple-generators/references/paywall-generator/overview.md), [`monetization`](../../monetization/overview.md)                                                                                                                                                                                                                                                                                            |
| Win-backs, retention messaging              | [`generators/win-back-offers`](../../../../apple-generators/references/win-back-offers/overview.md)                                                                                                                                                                                                                                                                                                                                                  |
| External purchase links / web checkout      | [`monetization/external-purchases`](../../monetization/external-purchases/overview.md)                                                                                                                                                                                                                                                                                                                                                               |
| Bundles, Family Sharing, volume licensing   | [`monetization/bundles-and-licensing`](../../monetization/bundles-and-licensing/overview.md)                                                                                                                                                                                                                                                                                                                                                         |
| Retention surfaces                          | [`generators/onboarding-generator`](../../../../apple-generators/references/onboarding-generator/overview.md), [`generators/push-notifications`](../../../../apple-generators/references/push-notifications/overview.md), [`generators/widget-generator`](../../../../apple-generators/references/widget-generator/overview.md), [`generators/live-activity-generator`](../../../../apple-generators/references/live-activity-generator/overview.md) |

## Caveats

- **Read-only on ASC.** The audit never mutates anything — not even analytics report setup (that
  routes to store-signals). Surface → score → route.
- **MANUAL honesty.** Ask once, in one batch. "I don't know" scores 🟠 _unverified_ — the
  scorecard tells the user what to go check, it never guesses.
- **⏳ items are rechecked every audit.** Apple ships announced features on its own schedule; each
  ⏳ stanza carries a dormant detection rule — when the feature is live, apply it and drop the flag.
- **Never reset the ratings summary** (P4.4). That item is a guardrail, not a task: resetting
  discards accumulated social proof and is almost never recoverable. Default ✅; flip to 🔴 only
  if a reset is planned or happened — then route to [`app-store/ratings-mechanics`](../../app-store/ratings-mechanics/overview.md) to stop it.
- Stable IDs. New items get new numbers; retired items keep their row with status `retired`.

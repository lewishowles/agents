# Originality Check

Decide, with evidence, whether an app is _distinct enough to exist_ — before you build it or submit it.

> At portfolio scale, shipping many similar small apps risks **Guideline 4.3 (spam / duplicate)**
> — this is the go/no-go distinctness gate that keeps that from happening.

## Where it fits (read the seams)

- **Not `rejection-handler`.** That works a rejection you _already have_. This is upstream — it
  prevents the 4.3 by catching sameness before you ship.
- **Not `competitive-analysis` / `market-research`.** Those size demand and position you in the
  market. This judges _distinctness_ (function + content + metadata) vs your own portfolio and vs
  near-identical competitors — a spam risk, not a demand question.
- **Two moments to run it:** at `validate` / `new-app` (don't build a dup) and before `submit`
  (don't trip 4.3). Also periodically across the portfolio (internal cannibalization / template-sameness).

## Prerequisites

- The app idea or a shipped app to evaluate (name, one-line function, target metadata).
- Optional: `.planning/VALIDATION.md` (competitor + market data). If missing/stale, gather fresh
  via WebSearch or the [`product/competitive-analysis`](../../product/competitive-analysis/overview.md) skill.
- Optional ASC access to read the developer's existing portfolio (`list_apps` / `get_metadata`).

## Flow

1. **Internal check (your own portfolio).** `list_apps` → for each shipped app read its positioning
   (`get_metadata`). Does the candidate overlap one you already ship in **function**, **code
   template**, or **metadata**? Two apps that differ only in theme/reskin = 4.3 risk.
2. **External check (the market).** Read `VALIDATION.md` if present; otherwise `WebSearch` for close
   look-alikes. Judge: is the core function a thin reskin of an existing app, or a genuine wedge?
3. **Distinctness scorecard.** Score each dimension _meaningful difference vs cosmetic_, and flag any
   that is only skin-deep:

   | Dimension          | Distinct if…                                                                |
   | ------------------ | --------------------------------------------------------------------------- |
   | **Function**       | it does something materially different, not a template swap                 |
   | **Content / data** | unique data or content, not a generic wrapper                               |
   | **Metadata**       | name / keywords / screenshots not near-identical to siblings or competitors |
   | **UX / value**     | a real reason a user picks _this_ one                                       |

4. **Verdict + remedy.**
   - **Distinct** → proceed.
   - **Borderline** → give concrete ways to differentiate (merge sibling apps into one configurable
     app, add the unique wedge, or drop it); if approved, name the specific wedge that MUST be built
     to clear 4.3.
   - **Duplicate** → recommend not shipping; consolidate any existing thin apps into one strong
     app instead.
5. **Record.** Write the verdict + reasoning to `.planning/` (VALIDATION or STATE). For a
   borderline-approved app, record the wedge as a build requirement so `plan`/`build` deliver it.

## Done

- A written verdict (distinct / borderline+wedge / duplicate) with per-dimension reasoning, and —
  if borderline — the specific differentiation that must ship before submission.

## Caveats

- **Cosmetic theming ≠ differentiation** — Apple judges function + metadata similarity, not intent.
- **Protect the account.** When in doubt between "borderline ship" and "consolidate," prefer one
  strong app over several thin ones.
- Guideline numbers/text drift — confirm current 4.3 wording at the
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (captured 2026-07).

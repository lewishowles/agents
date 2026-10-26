---
name: app-release
description: >
  Use this skill when planning or releasing an Apple app: market research,
  product specs, pricing, growth, App Store listings and marketing, a privacy
  policy or a pre-release review. Choose the topic and open only the relevant
  reference. Do not use it to generate Swift code or project files; use
  apple-generators for that work.
---

# Apple app product and release

Choose the task's topic below and open only its reference. Each topic group
starts with an overview that explains how its references fit together. The
references are a snapshot of the [pinned source](SOURCE.md), so check current
App Store rules and the law that applies to the app before relying on a claim
about either.

## Product planning and specs

- [Product overview](references/product/overview.md) and [workflow](references/product/WORKFLOW.md): Find the product planning sequence.
- [Idea generator](references/product/idea-generator/overview.md), [product discovery](references/product/product-agent/overview.md), [market research](references/product/market-research/overview.md) and [competitive analysis](references/product/competitive-analysis/overview.md): Explore and assess an app idea. Open the product discovery [reference](references/product/product-agent/REFERENCE.md) and [usage patterns](references/product/product-agent/examples/usage-patterns.md), or the example output for [market research](references/product/market-research/examples/market-analysis.json) and [competitive analysis](references/product/competitive-analysis/examples/analysis-output.json), only when needed.
- [Product requirements](references/product/prd-generator/overview.md), [architecture spec](references/product/architecture-spec/overview.md), [UX spec](references/product/ux-spec/overview.md) and [implementation spec](references/product/implementation-spec/overview.md): Write the relevant plan or coordinate a specification package.
- [Implementation guide](references/product/implementation-guide/overview.md) and [test spec](references/product/test-spec/overview.md): Plan delivery and verification.
- [Beta testing](references/product/beta-testing/overview.md), [localisation strategy](references/product/localization-strategy/overview.md) and [release spec](references/product/release-spec/overview.md): Prepare launch decisions and materials.
- [App naming](references/product/app-namer/overview.md): Choose and validate a name and subtitle before reserving the App Store listing.

## Growth and indie business

- [Growth overview](references/growth/overview.md): Choose a growth topic.
- [Indie business](references/growth/indie-business/overview.md): Plan an independent app business.
- [Community building](references/growth/community-building/overview.md) and [press and media](references/growth/press-media/overview.md): Plan outreach. Open the [pitch templates](references/growth/press-media/pitch-templates.md) when drafting a pitch.
- [Analytics interpretation](references/growth/analytics-interpretation/overview.md): Understand product metrics. Open the [metrics reference](references/growth/analytics-interpretation/metrics-reference.md) for definitions.
- [Store growth audit](references/growth/store-growth-audit/overview.md) and [store signals](references/growth/store-signals/overview.md): Find growth gaps and turn store evidence into a product backlog. Open their supporting checklists and ledger template as needed.

## Pricing

- [Monetisation overview](references/monetization/overview.md), [pricing models](references/monetization/pricing-models.md) and [app type guides](references/monetization/app-type-guides.md): Choose and assess an app pricing approach.
- [Bundles and licensing](references/monetization/bundles-and-licensing/overview.md) and [external purchases](references/monetization/external-purchases/overview.md): Review additional distribution and purchase options.
- See [paywall generation](../apple-generators/references/paywall-generator/overview.md), [subscription lifecycle](../apple-generators/references/subscription-lifecycle/overview.md) and [subscription offers](../apple-generators/references/subscription-offers/overview.md) when implementing a purchase flow.

## App Store listing and marketing

- [App Store overview](references/app-store/overview.md): Choose the listing or marketing task.
- [Keyword optimisation](references/app-store/keyword-optimizer/overview.md), [app description](references/app-store/app-description-writer/overview.md) and [screenshot planning](references/app-store/screenshot-planner/overview.md): Prepare listing text and images.
- [Marketing strategy](references/app-store/marketing-strategy/overview.md), [Apple Search Ads](references/app-store/apple-search-ads/overview.md) and [review responses](references/app-store/review-response-writer/overview.md): Plan promotion and customer communication. Open the strategy templates only for the relevant app model.
- [Rejection handling](references/app-store/rejection-handler/overview.md): Assess a review rejection with the [common rejections](references/app-store/rejection-handler/common-rejections.md) reference.
- [Ad attribution](references/app-store/ad-attribution/overview.md), [originality review](references/app-store/originality-check/overview.md), [ratings mechanics](references/app-store/ratings-mechanics/overview.md) and [web presence](references/app-store/web-presence/overview.md): Check attribution, submission originality, rating behaviour and discovery outside the store.
- [App Store assets](references/generators/app-store-assets/overview.md), [custom product pages](references/generators/custom-product-pages/overview.md), [featuring nominations](references/generators/featuring-nomination/overview.md) and [in-app events](references/generators/in-app-events/overview.md): Plan the relevant App Store material and open the topic's supporting template only when needed, such as the [in-app event templates](references/generators/in-app-events/templates.md).
- [Offer codes](references/generators/offer-codes-setup/overview.md), [pre-orders](references/generators/pre-orders/overview.md) and [product page optimisation](references/generators/product-page-optimization/overview.md): Plan an App Store launch or offer.

## Privacy and legal

- [Legal overview](references/legal/overview.md) and [privacy policy](references/legal/privacy-policy/overview.md): Draft a policy using the [templates](references/legal/privacy-policy/templates.md) when useful. Verify legal requirements with a qualified source before relying on the draft.
- See [consent flow generation](../apple-generators/references/consent-flow/overview.md) and [account deletion generation](../apple-generators/references/account-deletion/overview.md) for implementing related app features.

## Release review

- [Release review overview](references/release-review/overview.md): Choose a review checklist.
- [Distribution](references/release-review/distribution-checklist.md), [privacy](references/release-review/privacy-checklist.md), [security](references/release-review/security-checklist.md), [API design](references/release-review/api-design-checklist.md) and [UX polish](references/release-review/ux-polish-checklist.md): Review only the areas relevant to the release.

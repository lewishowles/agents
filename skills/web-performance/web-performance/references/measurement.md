# Web performance — measurement

## Tools

| Tool                            | What it measures                          | How to use                               |
| ------------------------------- | ----------------------------------------- | ---------------------------------------- |
| **Lighthouse**                  | All CWVs, accessibility, SEO              | DevTools → Lighthouse → run in Incognito |
| **PageSpeed Insights**          | Real-world CWV data (CrUX) + lab scores   | pagespeed.web.dev                        |
| **WebPageTest**                 | Waterfall, filmstrip, multi-region        | webpagetest.org                          |
| **Chrome DevTools Performance** | Frame timeline, long tasks, layout shifts | F12 → Performance → record               |
| **Bundle visualiser**           | Bundle composition, tree-shaking gaps     | `rollup-plugin-visualizer`               |

Always measure production builds — dev mode disables minification, tree-shaking, and code splitting, so numbers are meaningless.

## Lighthouse CI

Run Lighthouse in CI to catch regressions before they ship:

```bash
bun add -D @lhci/cli
```

```yaml
# .github/workflows/lhci.yml
- name: Lighthouse CI
  run: bunx lhci autorun
  env:
    LHCI_GITHUB_APP_TOKEN: ${{ secrets.LHCI_GITHUB_APP_TOKEN }}
```

```javascript
// lighthouserc.js
module.exports = {
  ci: {
    collect: { url: ["http://localhost:4173/"] },
    assert: {
      assertions: {
        "categories:performance": ["warn", { minScore: 0.9 }],
        "categories:accessibility": ["error", { minScore: 0.95 }],
      },
    },
  },
};
```

## Web Vitals API

Measure real-user performance in production:

```bash
bun add web-vitals
```

```javascript
import { onCLS, onINP, onLCP } from "web-vitals";

function sendToAnalytics({ name, value, id }) {
  // Send to your analytics endpoint
  console.log({ name, value, id });
}

onCLS(sendToAnalytics);
onINP(sendToAnalytics);
onLCP(sendToAnalytics);
```

Call this in your app entry point (`main.js`). The metrics fire automatically at the appropriate lifecycle points.

## Bundle analysis

Add to `vite.config.ts`:

```typescript
import { visualizer } from "rollup-plugin-visualizer";

export default defineConfig({
  plugins: [vue(), visualizer({ open: true, gzipSize: true, filename: "dist/stats.html" })],
});
```

Run `bun run build` — the report opens automatically. Look for:

- Unexpectedly large chunks (likely missing dynamic imports)
- Duplicate dependencies (two versions of the same package)
- Libraries included whole when only a subset is needed (lodash, date-fns)

## Common performance issues and fixes

| Symptom        | Likely cause                  | Fix                                     |
| -------------- | ----------------------------- | --------------------------------------- |
| High LCP       | Hero image not preloaded      | Add `<link rel="preload">`              |
| High CLS       | Images without dimensions     | Add `width`/`height` or `aspect-ratio`  |
| High INP       | Long event handlers           | Defer non-critical work; break up tasks |
| Large bundle   | Missing route-level splitting | Dynamic import route components         |
| Slow font load | No `font-display`             | Add `font-display: swap`                |
| CLS from fonts | FOUT on web fonts             | Use `font-display: optional` or preload |

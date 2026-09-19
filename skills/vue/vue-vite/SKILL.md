---
name: vue-vite
description: >
  Use this skill when configuring vite.config.ts, managing environment variables, or troubleshooting build/dev server issues. Covers config structure, environment variables, security boundaries, library mode, dev vs build differences, and common pitfalls.
filePatterns: ["vite.config.ts", "vite.config.js"]
pathPatterns: []
---
> Modified from [ECC `vite-patterns`](https://github.com/affaan-m/everything-claude-code/blob/main/skills/vite-patterns/SKILL.md) — MIT © 2026 Affaan Mustafa. Adapted to focus on config, security, and build patterns relevant to Vue projects; omitted plugin authoring and framework-specific HMR details.

# Vite patterns

Build patterns for Vite. Dev serves native ESM with on-demand transforms; build bundles with Rollup tree-shaking.

## Config structure

### Basic config

```typescript
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { "@": new URL("./src", import.meta.url).pathname },
  },
});
```

### Conditional config

```typescript
import { defineConfig, loadEnv } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), ["VITE_"]);

  return {
    plugins: [vue()],
    server: command === "serve" ? { port: 5173 } : undefined,
    define: {
      __API_URL__: JSON.stringify(env.VITE_API_URL),
    },
  };
});
```

### Key config options

| Key               | Default   | Notes                                               |
| ----------------- | --------- | --------------------------------------------------- |
| `root`            | `"."`     | Project root (where `index.html` lives)             |
| `base`            | `"/"`     | Public base path for deployed assets                |
| `envPrefix`       | `"VITE_"` | Prefix for client-exposed env vars                  |
| `build.outDir`    | `"dist"`  | Output directory                                    |
| `build.minify`    | `"oxc"`   | Minifier (`"oxc"`, `"terser"`, or `false`)          |
| `build.sourcemap` | `false`   | `true`, `"inline"`, or `"hidden"` (disable in prod) |

## Environment variables

Vite loads .env, .env.local, .env.[mode], .env.[mode].local in order (later overrides earlier). .local files are gitignored.

### Client-side access

Only `VITE_` vars are exposed to client code:

```typescript
import.meta.env.VITE_API_URL;
import.meta.env.MODE; // "development" | "production" | custom
import.meta.env.BASE_URL; // base config value
import.meta.env.DEV; // boolean
import.meta.env.PROD; // boolean
```

### Using env in config

```typescript
import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), ["VITE_", "APP_"]);

  return {
    define: { __API_URL__: JSON.stringify(env.VITE_API_URL) },
  };
});
```

## Security

### `VITE_` prefix is not a security boundary

VITE\_ vars are statically inlined at build time. Minification and disabled source maps don't hide them.

**Rule:** only public values (API URLs, feature flags, public keys) go in `VITE_`. Secrets must live server-side behind an API.

### The `loadEnv("")` trap

```typescript
// Bad: passing "" loads all env vars, including server secrets.
const env = loadEnv(mode, process.cwd(), "");

// Good: explicit prefix list.
const env = loadEnv(mode, process.cwd(), ["VITE_", "APP_"]);
```

### Source maps in production

Production source maps leak source. Disable unless uploading to error tracker:

```typescript
build: {
  sourcemap: false;
} // default — keep it this way
```

### .gitignore checklist

- `.env.local`, `.env.*.local` — local overrides with secrets
- `dist/` — build output
- `node_modules/.vite` — pre-bundle cache (stale entries cause phantom errors)

## Dev vs build

Dev uses esbuild, build uses Rollup (CJS may differ). Verify with vite build && vite preview before deploy.

vite build doesn't type-check; ship type errors unless CI runs tsc --noEmit.

## Imports and assets

Cross-directory imports use the `@` alias (`@/layout/...`), not relative `../../../` paths. Relative imports are fine within a directory or one level up.

```typescript
// File-system driven imports — no hand-maintained registries
const modules = import.meta.glob("./pages/**/*.vue");

// Asset query imports when the representation matters
import iconUrl from "./icon.svg?url";
import shaderSource from "./shader.glsl?raw";
```

## Plugins

- Order plugins intentionally (framework plugins before analysis/transform)
- Use virtual modules only when config-time data must become runtime-importable code
- Check Vite docs for migration (Rolldown, Oxc, beta features)

For library mode, SSR, and common pitfalls (stale chunks, Docker, monorepo, barrel files, import extensions, stale cache), see [references/advanced.md](references/advanced.md).

## Completion

For Vite changes affecting rendered UI, run [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) before handoff.

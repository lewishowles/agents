# Vite patterns — advanced

## Library mode

Publishing an npm package: use `build.lib`. Two footguns:

1. **Types not emitted** — add `vite-plugin-dts` or run `tsc --emitDeclarationOnly` separately.
2. **Peer deps must be externalised** — unlisted peers bundle into the library, causing duplicate-runtime errors in consumers.

```typescript
build: {
	lib: {
		entry: "src/index.ts",
		formats: ["es", "cjs"],
		fileName: (format) => `my-lib.${format}.js`,
	},
	rolldownOptions: {
		external: ["vue", "vue-router"], // every peer dep
	},
}
```

## SSR mode

- Treat SSR builds as a separate runtime: browser globals, env variables, and asset URLs may behave differently.
- Keep client-only logic behind component lifecycle hooks or explicit environment guards.
- Test both dev SSR and production build output when changing Vite SSR config.

## Common pitfalls

### Stale chunks after deployment

New builds produce new chunk hashes. Users with active sessions request old filenames that no longer exist.

Mitigations:

- Keep old `dist/assets/` files live for the deployment window.
- Catch dynamic import errors in the router and force a page reload.

### Docker and containers

Vite binds to `localhost` by default — unreachable from outside a container:

```typescript
server: {
	host: true,            // bind 0.0.0.0
	hmr: { clientPort: 3000 }, // if behind reverse proxy
}
```

### Monorepo file access

Vite restricts file serving to the project root. Packages outside root are blocked:

```typescript
server: {
	fs: { allow: [".."] }, // allow workspace root
}
```

### Barrel files slow the dev server

Barrel files (`index.ts` re-exporting everything) force Vite to load every re-exported file even when importing a single symbol:

```typescript
// Bad: forces load of whole barrel
import { slash } from "@/utils";

// Good: direct import
import { slash } from "@/utils/slash";
```

### Explicit import extensions

Each implicit extension triggers multiple filesystem checks. In large codebases this adds up:

```typescript
// Bad
import Component from "./Component";

// Good
import Component from "./Component.vue";
```

### Stale pre-bundle cache

`node_modules/.vite` causes phantom errors when deps change. Clear when switching branches or after patching deps:

```bash
rm -rf node_modules/.vite
```

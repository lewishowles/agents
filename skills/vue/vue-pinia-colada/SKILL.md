---
name: vue-pinia-colada
description: >
  Use this skill when working with @pinia/colada for async data fetching and server state in Vue projects. TRIGGER when: code imports from `@pinia/colada`, uses `useQuery`, `useMutation`, `defineQuery`, `defineMutation`, `useQueryCache`, or `invalidateQueries`; when setting up async data fetching in a Vue project; when working in `src/queries/`.
filePatterns: []
pathPatterns: ["/queries/", "/mutations/"]
---
# Pinia Colada

Pinia Colada manages Vue server state: caching, deduplication, background revalidation, and mutation coordination. It sits above fetch/API functions.

## Setup

```bash
bun add pinia @pinia/colada
bun add -D @pinia/colada-devtools
```

```js
// main.js
import { createApp } from "vue";
import { createPinia } from "pinia";
import { PiniaColada } from "@pinia/colada";

const app = createApp(App);

app.use(createPinia());
app.use(PiniaColada);
```

```vue
<!-- App.vue — devtools only, never shipped to production -->
<script setup>
import { PiniaColadaDevtools } from "@pinia/colada-devtools";
</script>

<template>
	<router-view />

	<pinia-colada-devtools />
</template>
```

## Default conventions

Use Colada for server state (not transport layer). Isolate API clients; keep cache keys and query logic in `src/queries/`.

Prefer feature folders once a resource has queries and mutations:

```
src/queries/auth/
├── index.js          # Public exports only
├── current-user.js   # Current user query + useCurrentUser()
└── login.js          # Login mutation + useAuth()
```

Import from feature folders, not implementation files:

```js
import { useAuth, useCurrentUser } from "@/queries/auth";
```

Name reusable definitions `*QueryOptions` / `*MutationOptions`; name live return values after resource/action:

```js
export const currentUserQueryOptions = defineQueryOptions({
	key: CURRENT_USER_QUERY_KEY,
	query: getCurrentUser,
});

const currentUser = useQuery(() => ({
	...currentUserQueryOptions,
	enabled: hasAuthToken(),
}));
```

Mental model:

- `currentUserQueryOptions` — reusable recipe: key + fetcher
- `currentUser` — live query state from `useQuery()`
- `userDetails` — derived data object exposed to components

Wrappers: use when removing repeated setup or exposing derived values. Auth: prefer token guards; use route middleware for access decisions, not preloading. Activate queries in components via enabled flag.

## Key factories

Centralise cache keys in query file. Parent keys create hierarchy: invalidating parent invalidates children.

```js
// src/queries/contacts.js
export const CONTACT_KEYS = {
	root: ["contacts"],
	byId: (id) => [...CONTACT_KEYS.root, id],
	byIdWithNotes: (id) => [...CONTACT_KEYS.byId(id), { notes: true }],
};
```

Invalidating `CONTACT_KEYS.root` invalidates all contacts queries; `CONTACT_KEYS.byId(id)` invalidates that contact and notes.

For singleton resources, keep keys simple:

```js
export const CURRENT_USER_QUERY_KEY = ["user"];
```

For collections, include every input that changes returned data:

```js
export const ALERT_KEYS = {
	root: ["alerts"],
	list: (siteId, filters) => [...ALERT_KEYS.root, "list", siteId, filters],
	byId: (alertId) => [...ALERT_KEYS.root, "detail", alertId],
};
```

## API patterns

Consult **[references/api.md](references/api.md)** when choosing between `defineQueryOptions`, `useQuery`, `useMutation`, `defineMutationOptions`, `defineMutation`, `defineQuery`, `refresh()`, `refetch()`, `state`, and `asyncStatus`.

## Active queries

Active query: used by live Vue code via `useQuery()` or wrapper. Invalidation triggers refetch; inactive becomes stale.

## Folder structure

```
src/
├── api/          # Raw fetch functions — no cache keys, no query logic
│   └── contacts.js
└── queries/      # Feature folders: keys + options + wrappers
    └── contacts/
        ├── index.js
        ├── list.js
        └── update.js
```

State management responsibilities:

- **Pinia stores** — UI state, user preferences, app-wide flags
- **Pinia Colada** — server data: fetching, caching, revalidation
- **Plain composables** — local shared state that doesn't need caching

## Advanced topics

- **[references/advanced-patterns.md](references/advanced-patterns.md)** — optimistic updates, infinite queries, paginated queries, query cancellation, SSR, Nuxt
- **[references/plugins.md](references/plugins.md)** — retry, delay, auto-refetch, cache persistence, query hooks, custom plugins
- **[references/query-cache.md](references/query-cache.md)** — direct cache access, `invalidateQueries` variants, mutation cache

## Completion

For server-state changes that affect rendered UI, run [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) before handoff.

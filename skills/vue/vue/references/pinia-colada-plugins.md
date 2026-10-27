# Plugins

## Registration

```js
import { PiniaColada } from "@pinia/colada";
import { PiniaColadaRetry } from "@pinia/colada-plugin-retry";
import { PiniaColadaDelay } from "@pinia/colada-plugin-delay";

app.use(PiniaColada, {
	plugins: [PiniaColadaRetry(), PiniaColadaDelay()],
});
```

Plugins run in the order they are listed.

## Official plugins

### Retry (`@pinia/colada-plugin-retry`)

Retries failed queries with configurable backoff.

```js
PiniaColadaRetry({
	retry: 3,        // maximum retries (default: 3)
	delay: 1000,     // ms between retries, or (count) => ms for custom backoff
})
```

Per-query override:

```js
useQuery({ ...myQuery, retry: 0 });                                    // disable
useQuery({ ...myQuery, retry: (count, error) => count < 5 });          // conditional
```

Adds extensions to each entry: `isRetrying`, `retryCount`, `retryError`.

### Delay (`@pinia/colada-plugin-delay`)

Delays `asyncStatus` becoming `'loading'` by a short interval. Prevents the loading spinner flashing on fast responses — the UI stays stable when data arrives before the delay expires.

```js
PiniaColadaDelay({
	delay: 200,       // ms (default: 200)
	// query: 300,    // queries only
	// mutation: 100, // mutations only
})
```

Per-query override:

```js
useQuery({ ...myQuery, delay: 500 });
```

Adds extension: `isDelaying`.

### Auto-refetch (`@pinia/colada-plugin-auto-refetch`)

Refetches stale queries when the window regains focus or the network reconnects.

```js
PiniaColadaAutoRefetch()
```

Requires `staleTime` to be configured — queries only refetch if their cached data is considered stale.

Per-query opt-out:

```js
useQuery({ ...myQuery, autoRefetch: false });
```

### Cache persister (`@pinia/colada-plugin-cache-persister`)

Persists the query cache to storage so data survives page reloads.

```js
PiniaColadaCachePersister({
	key: "pc:cache",           // localStorage key
	storage: localStorage,     // default: localStorage
	// debounce: 1000,         // ms between writes
	// filter: (entry) => true // which entries to persist
})
```

### Query hooks (built-in)

Global callbacks for query lifecycle events. No separate install — part of `@pinia/colada`.

```js
import { PiniaColada, PiniaColadaQueryHooksPlugin } from "@pinia/colada";

app.use(PiniaColada, {
	plugins: [
		PiniaColadaQueryHooksPlugin({
			onSuccess(data, entry) { /* ... */ },
			onError(error, entry) {
				// entry.meta is available for per-query metadata.
				if (entry.meta?.errorMessage) {
					showToast(entry.meta.errorMessage);
				}
			},
			onSettled(data, error, entry) { /* ... */ },
		}),
	],
});
```

Attach metadata to a query with `meta`:

```js
useQuery({
	...contactListQuery,
	meta: { errorMessage: "Could not load contacts." },
});
```

## Writing a custom plugin

A plugin is a factory function that returns a `PiniaColadaPlugin`.

```js
import { useMutationCache } from "@pinia/colada";
import { shallowRef } from "vue";

/**
 * Example plugin that tracks the last error time for each query entry.
 */
export function PiniaColadaErrorTimestamp() {
	return ({ queryCache, scope }) => {
		queryCache.$onAction(({ name, args, after, onError }) => {
			if (name === "extend") {
				const [entry] = args;

				scope.run(() => {
					entry.ext.lastErrorAt = shallowRef(null);
				});
			} else if (name === "fetch") {
				const [entry] = args;

				onError(() => {
					entry.ext.lastErrorAt.value = new Date();
				});
			}
		});
	};
}
```

### Query lifecycle

1. `ensure(options)` — get or create a cache entry
2. `extend(entry)` — first `ensure` only; plugins attach extensions here
3. `fetch(entry)` — execute the query function
4. `setEntryState(entry, state)` — canonical state update
5. `remove(entry)` — garbage collection or manual removal

### Mutation lifecycle

1. `create(options)` → `extend(entry)` — on `useMutation()` call
2. `ensure(entry, vars)` → `mutate(entry)` — on each `mutateAsync()` call
3. `setEntryState(entry, state)` — state transitions

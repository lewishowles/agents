# Advanced patterns

## Optimistic updates via cache

Use when the mutation and the query it affects are in different components. Pattern: save previous state → apply optimistic change → cancel any in-flight queries → rollback on error → invalidate on settle.

```js
import { useMutation, useQueryCache } from "@pinia/colada";
import { BOOKING_KEYS } from "@/queries/bookings";
import { updateBooking } from "@/api/bookings";

const queryCache = useQueryCache();

const { mutate } = useMutation({
	mutation: (booking) => updateBooking(booking),

	onMutate(booking) {
		const previous = queryCache.getQueryData(BOOKING_KEYS.byId(booking.id));
		const optimistic = { ...previous, ...booking };

		queryCache.setQueryData(BOOKING_KEYS.byId(booking.id), optimistic);
		queryCache.cancelQueries({ key: BOOKING_KEYS.byId(booking.id) });

		return { previous, optimistic };
	},

	onError(_error, booking, { optimistic, previous }) {
		// Skip rollback if the cache was updated by a later mutation.
		if (optimistic === queryCache.getQueryData(BOOKING_KEYS.byId(booking.id))) {
			queryCache.setQueryData(BOOKING_KEYS.byId(booking.id), previous);
		}
	},

	onSuccess(serverBooking, _vars, { optimistic }) {
		// Swap the optimistic entry for what the server returned.
		queryCache.setQueryData(BOOKING_KEYS.byId(serverBooking.id), serverBooking);
	},

	onSettled(_data, _error, booking) {
		queryCache.invalidateQueries({ key: BOOKING_KEYS.byId(booking.id) });
	},
});
```

### Appending to a list

```js
onMutate(title) {
	const previous = queryCache.getQueryData(["bookings"]);
	const pending = { id: crypto.randomUUID(), title };

	queryCache.setQueryData(["bookings"], [...(previous || []), pending]);
	queryCache.cancelQueries({ key: ["bookings"] });

	return { previous, pending };
},

onSuccess(serverBooking, _vars, { pending }) {
	const list = queryCache.getQueryData(["bookings"]) || [];
	const index = list.findIndex((b) => b.id === pending.id);

	if (index >= 0) {
		const updated = list.slice();

		updated.splice(index, 1, serverBooking);
		queryCache.setQueryData(["bookings"], updated);
	}
},
```

## Optimistic updates via UI

Use when the mutation and query are in the same component. Simpler — no cache manipulation needed.

```vue
<script setup>
import { useQuery, useMutation, useQueryCache } from "@pinia/colada";
import { bookingListQuery } from "@/queries/bookings";
import { createBooking } from "@/api/bookings";

const { data: bookings } = useQuery(bookingListQuery);
const queryCache = useQueryCache();

const {
	mutate: addBooking,
	isLoading,
	variables: pendingTitle,
} = useMutation({
	mutation: (title) => createBooking(title),
	async onSettled() {
		await queryCache.invalidateQueries({ key: ["bookings"] });
	},
});
</script>

<template>
	<ul>
		<li v-for="booking in bookings" :key="booking.id">{{ booking.title }}</li>
		<li v-if="isLoading" style="opacity: 0.5">{{ pendingTitle }}</li>
	</ul>
</template>
```

For cross-component optimistic state, give the mutation a `key` and read it elsewhere via `mutationCache.getEntries({ key })`.

## Infinite queries

All pages live in one cache entry. The page parameter must NOT be in the cache key — only filters and search terms go in the key. Changing the key resets the query.

```js
import { useInfiniteQuery } from "@pinia/colada";

const { data, hasNextPage, loadNextPage, asyncStatus } = useInfiniteQuery({
	key: () => ["notifications", { unreadOnly: unreadOnly.value }],
	initialPageParam: 1,
	query: ({ pageParam }) => fetchNotifications({ page: pageParam }),
	getNextPageParam: (lastPage) => lastPage.nextPage ?? null,
});

// data.value.pages — array of page results
// data.value.pageParams — param used for each page
```

Cursor-based pagination:

```js
useInfiniteQuery({
	key: ["activity-feed"],
	initialPageParam: null,
	query: ({ pageParam }) => fetchActivity({ cursor: pageParam }),
	getNextPageParam: (lastPage) => lastPage.nextCursor ?? null,
});
```

## Paginated queries

Each page is a separate cache entry. The page IS part of the key. Use `placeholderData` so the previous page stays visible while the next loads.

```js
const page = ref(1);

const { data, isPlaceholderData } = useQuery({
	key: () => ["contacts", { page: page.value }],
	query: () => getContacts({ page: page.value }),
	placeholderData: (previous) => previous,
});
```

## Query cancellation

The `query` function receives a `signal` (AbortSignal). Pass it to `fetch` so in-flight requests are cancelled when the query is superseded.

```js
useQuery({
	key: CONTACT_KEYS.root,
	query: ({ signal }) => fetch("/api/contacts", { signal }).then((r) => r.json()),
});
```

Cancel from the cache without triggering a refetch — useful in optimistic update flows:

```js
queryCache.cancelQueries({ key: CONTACT_KEYS.byId(id) });
```

## SSR

Serialise the cache on the server, hydrate it on the client using `devalue`.

```js
// Server
import { serialize } from "devalue";
import { serializeQueryCache } from "@pinia/colada";

const cacheData = serializeQueryCache(queryCache);
// Send serialize(cacheData) to client in the HTML payload.
```

```js
// Client
import { parse } from "devalue";
import { hydrateQueryCache } from "@pinia/colada";

hydrateQueryCache(queryCache, parse(serverData));
```

Lazy queries (client-only, skip server fetch):

```js
// Disable on server, enable on mount.
useQuery({ ...myQuery, enabled: false });
```

## Nuxt

```bash
bun add @pinia/colada-nuxt
```

```js
// nuxt.config.ts
export default defineNuxtConfig({
	modules: ["@pinia/colada-nuxt"],
});
```

- No `await` needed in setup — SSR is handled automatically by the module
- Use `$fetch` in query functions so they work on both server and client
- In `defineQuery`, import `useRoute` from `vue-router` directly, not from Nuxt auto-imports
- Configure via `colada.options.ts` in the project root

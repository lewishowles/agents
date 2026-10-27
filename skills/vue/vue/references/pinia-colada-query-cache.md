# Query cache

## Access

`useQueryCache()` is available in component setup, Pinia stores, and router navigation guards — anywhere `inject()` works.

```js
import { useQueryCache } from "@pinia/colada";

const queryCache = useQueryCache();
```

## getQueryData / setQueryData

```js
import { useQueryCache } from "@pinia/colada";
import { contactByIdQuery } from "@/queries/contacts";

const queryCache = useQueryCache();

// Read from cache — return type inferred from the query definition.
const contact = queryCache.getQueryData(contactByIdQuery("42").key);

// Write to cache — useful for optimistic updates.
queryCache.setQueryData(contactByIdQuery("42").key, updatedContact);
```

## invalidateQueries

Marks matching entries as stale. Active queries refetch automatically; inactive ones refetch on next use.

```js
// Hierarchical — invalidates all queries whose key starts with ["contacts"].
queryCache.invalidateQueries({ key: ["contacts"] });

// Exact match only.
queryCache.invalidateQueries({ key: ["contacts"], exact: true });

// Predicate — full control over which entries match.
queryCache.invalidateQueries({
	predicate: (entry) => entry.key[0] === "contacts" || entry.key[0] === "tasks",
});

// Refetch all matching entries, including inactive ones.
queryCache.invalidateQueries({ key: ["contacts"] }, "all");

// Invalidate everything.
queryCache.invalidateQueries();
```

Awaiting `invalidateQueries` inside `onSettled` keeps the mutation in loading state until the refetch completes — useful when the UI should only update after fresh data arrives.

```js
onSettled() {
	await queryCache.invalidateQueries({ key: ["contacts"] });
},
```

## cancelQueries

Cancels in-flight requests without triggering a refetch. Used in optimistic update flows to prevent a stale server response overwriting the optimistic state.

```js
queryCache.cancelQueries({ key: CONTACT_KEYS.byId(id) });
```

## getEntries

Access raw cache entries directly.

```js
const entries = queryCache.getEntries({ key: ["contacts"] });
// entry.state, entry.meta, entry.keyHash, entry.when
```

## Mutation cache

Opt in separately — tree-shakable.

```js
import { useMutationCache } from "@pinia/colada";

const mutationCache = useMutationCache();

// Read mutation state from another component.
// The mutation must be given a key for this to work.
const entries = mutationCache.getEntries({ key: ["createContact"] });
const isCreating = entries[0]?.asyncStatus.value === "loading";
const pendingVars = entries[0]?.vars;
```

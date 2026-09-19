# Pinia Colada API patterns

## defineQueryOptions

Combine a key factory with a query function. Pass the definition to `useQuery` instead of inlining keys.

**Static** (no parameters):

```js
import { defineQueryOptions } from "@pinia/colada";
import { getContacts } from "@/api/contacts";

export const contactListQueryOptions = defineQueryOptions({
	key: CONTACT_KEYS.root,
	query: () => getContacts(),
});
```

**Dynamic** (with parameters):

```js
import { getContactById } from "@/api/contacts";

export const contactByIdQueryOptions = defineQueryOptions((id) => ({
	key: CONTACT_KEYS.byId(id),
	query: () => getContactById(id),
}));
```

## useQuery

Pass dynamic options as a getter so Vue tracks reactivity.

```vue
<script setup>
import { useQuery } from "@pinia/colada";
import { useRoute } from "vue-router";
import { contactByIdQueryOptions } from "@/queries/contacts";

const route = useRoute();

// Getter function — re-evaluates reactively when route.params changes.
const contact = useQuery(() => contactByIdQueryOptions(route.params.contactId));
</script>

<template>
	<div v-if="contact.asyncStatus.value === 'loading'">Loading…</div>
	<div v-else-if="contact.state.value.status === 'error'">{{ contact.state.value.error.message }}</div>
	<div v-else-if="contact.state.value.data">{{ contact.state.value.data.name }}</div>
</template>
```

Use `state`, not destructured `data`/`error`, for status checks; it narrows types in conditionals.

### Pausing a query

Use `enabled` to pause until required data exists.

```js
const selectedId = ref(null);

useQuery({
	key: () => ["contacts", selectedId.value],
	query: () => getContactById(selectedId.value),
	enabled: () => selectedId.value != null,
});
```

### Spreading extra options

Override individual options without redefining the query.

```js
useQuery(() => ({
	...contactByIdQueryOptions(route.params.contactId),
	enabled: isReady.value,
}));
```

## useMutation

```js
import { useMutation, useQueryCache } from "@pinia/colada";
import { CONTACT_KEYS } from "@/queries/contacts";
import { updateContact } from "@/api/contacts";

const queryCache = useQueryCache();

const { mutate: saveContact, asyncStatus } = useMutation({
	mutation: (contact) => updateContact(contact),
	onSettled(_data, _error, contact) {
		queryCache.invalidateQueries({ key: CONTACT_KEYS.byId(contact.id) });
	},
});
```

- `mutate()` — fire-and-forget, catches errors silently
- `mutateAsync()` — returns a promise, re-throws errors

Prefer `mutateAsync()` when the caller already has `try/catch`, such as login forms or save buttons that redirect after success.

## defineMutationOptions and defineMutation

Use `defineMutationOptions` for reusable mutation recipes. Use `defineMutation` only when the wrapper needs shared reactive state.

```js
// src/queries/contacts/delete.js
import { defineMutationOptions, useMutation, useQueryCache } from "@pinia/colada";
import { CONTACT_KEYS } from "@/queries/contacts";
import { deleteContact } from "@/api/contacts";

export const deleteContactMutationOptions = defineMutationOptions({
	mutation: (id) => deleteContact(id),
});

export function useDeleteContact() {
	const queryCache = useQueryCache();

	return useMutation({
		...deleteContactMutationOptions,

		onSettled(_data, _error, id) {
			queryCache.invalidateQueries({ key: CONTACT_KEYS.byId(id) });
			queryCache.invalidateQueries({ key: CONTACT_KEYS.root, exact: true });
		},
	});
}
```

## defineQuery

Shares reactive state, such as search refs or filters, across components using the same query. Without it, each component gets its own internal refs.

```js
// src/queries/contacts.js
import { defineQuery, useQuery } from "@pinia/colada";
import { ref } from "vue";
import { searchContacts } from "@/api/contacts";

export const useContactSearch = defineQuery(() => {
	// Shared across all components using this query.
	const search = ref("");

	const { state, ...rest } = useQuery({
		key: () => ["contacts", { search: search.value }],
		query: () => searchContacts(search.value),
	});

	return { ...rest, contacts: state, search };
});
```

## refresh() vs refetch()

| Method | Behaviour |
|--------|-----------|
| `refresh()` | Reuses any in-flight request; skips if data is still fresh (`staleTime`). Prefer this. |
| `refetch()` | Always triggers a new network request regardless of cache state. |

Pass `true` when the caller handles failures with `try/catch`:

```js
await currentUser.refetch(true);
```

## State and status

| Property | Values | What it tells you |
|----------|--------|-------------------|
| `state.status` | `'pending'` → `'success'` \| `'error'` | Whether data has ever resolved |
| `asyncStatus` | `'idle'` \| `'loading'` | Whether a fetch is currently in progress |

These are separate. A query can have `state.status === 'success'` from earlier data and `asyncStatus === 'loading'` while refreshing.
